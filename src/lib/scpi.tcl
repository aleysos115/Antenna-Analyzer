#
# scpi.tcl -- a small transport-agnostic SCPI client.
#
# Two transports are supported:
#   connect_tcp host port      -- raw TCP socket (LAN/VXI-11-less "SCPI raw" port,
#                                  e.g. port 5025, or a serial-to-LAN bridge)
#   connect_usbtmc devicefile  -- a USBTMC character device on Linux, e.g.
#                                  /dev/usbtmc0
#
# Both are exposed through the same five calls: connect_*, write, query,
# query_block, disconnect. Everything above this layer (lib/driver.tcl and
# up) only ever calls those five, so swapping transports never touches the
# instrument-specific code.
#
# Responsiveness: `write`/`query`/`query_block` wait for the instrument using
# `vwait` on a non-blocking channel armed with a `fileevent`, not a blocking
# read. `vwait` re-enters Tcl's event loop while it waits, so Tk keeps
# painting, keeps taking button clicks, and a Cancel button click made while
# a query is in flight is processed the moment that query returns (see
# docs/architecture.rst for why this made an explicit sweep coroutine
# unnecessary). A watchdog `after` cancels the wait -- and raises an error --
# if the instrument never replies, e.g. because a mnemonic is wrong.
#
# USBTMC caveat: the Linux usbtmc character device does not reliably support
# poll()/select() on every kernel version, so fileevent-driven waits are not
# trustworthy there. connect_usbtmc therefore switches the client into
# "sync" mode, which uses plain blocking reads instead. That means a USBTMC
# session can briefly freeze the GUI during a slow acquisition; LAN is the
# better transport for a responsive GUI if your instrument offers both. See
# docs/troubleshooting.rst.
#
# Depends on: nothing (pure Tcl, no external packages)
#
namespace eval ::aa::scpi {
    variable chan        ""     ;# the Tcl channel, once connected
    variable async       1      ;# 1 = non-blocking + fileevent + vwait, 0 = plain blocking
    variable timeout_ms  4000   ;# per-operation watchdog
    variable connected   0
    variable logcb       ""     ;# script prefix: {*}$logcb $direction $text
    variable _ready       ""    ;# scratch var vwait waits on (single connection only)

    namespace export connect_tcp connect_usbtmc disconnect connected \
                      write query query_block check_errors \
                      set_log_callback set_timeout
}

## set_log_callback cb -- cb is invoked as "{*}$cb $direction $text" for every
## line sent or received, $direction one of TX RX ERR INFO. Used to drive the
## GUI's SCPI console tab; pass "" to silence logging.
proc ::aa::scpi::set_log_callback {cb} { variable logcb; set logcb $cb }
proc ::aa::scpi::_log {dir text} {
    variable logcb
    if {$logcb ne ""} { catch { uplevel #0 [linsert $logcb end $dir $text] } }
}

## set_timeout ms -- change the per-operation watchdog (default 4000 ms).
## Raise this for instruments that average many acquisitions per :SINGle.
proc ::aa::scpi::set_timeout {ms} { variable timeout_ms; set timeout_ms $ms }

proc ::aa::scpi::connected {} { variable connected; return $connected }

## disconnect -- close the channel if one is open. Safe to call repeatedly.
proc ::aa::scpi::disconnect {} {
    variable chan; variable connected
    if {$chan ne ""} { catch {close $chan} }
    set chan ""
    set connected 0
}

## connect_tcp host port ?timeout_ms? -- open a raw TCP SCPI socket.
## Uses an async connect + writable-fileevent so a wrong host/port doesn't
## hang the caller for the OS-level TCP timeout (which can be a minute or more).
proc ::aa::scpi::connect_tcp {host port {timeout_ms 3000}} {
    variable chan; variable connected; variable async; variable _ready
    disconnect
    set async 1
    _log INFO "connecting to $host:$port ..."
    set chan [socket -async $host $port]
    fconfigure $chan -translation binary -blocking 0 -buffering none
    set _ready ""
    fileevent $chan writable [namespace code {set _ready ok}]
    set timer [after $timeout_ms [namespace code {set _ready timeout}]]
    vwait ::aa::scpi::_ready
    after cancel $timer
    fileevent $chan writable {}
    if {$_ready ne "ok"} {
        catch {close $chan}; set chan ""
        _log ERR "connect timed out"
        error "connect to $host:$port timed out"
    }
    set sockerr [fconfigure $chan -error]
    if {$sockerr ne ""} {
        catch {close $chan}; set chan ""
        _log ERR "connect failed: $sockerr"
        error "connect to $host:$port failed: $sockerr"
    }
    set connected 1
    _log INFO "connected"
    return 1
}

## connect_usbtmc devicefile -- open a USBTMC character device, e.g.
## /dev/usbtmc0. Requires read/write permission on the device (see
## docs/installation.rst for the udev rule).
proc ::aa::scpi::connect_usbtmc {devicefile} {
    variable chan; variable connected; variable async
    disconnect
    _log INFO "opening $devicefile ..."
    set chan [open $devicefile r+]
    fconfigure $chan -translation binary -buffering none -blocking 1
    set async 0
    set connected 1
    _log INFO "connected (sync/USBTMC mode)"
    return 1
}

# ------------------------------------------------------------- wait helpers
# Block the *caller*, without blocking Tk, until $chan is readable or the
# watchdog fires. Only used when $async is true (TCP transport).
proc ::aa::scpi::_wait_readable {} {
    variable chan; variable timeout_ms; variable _ready
    set _ready ""
    fileevent $chan readable [namespace code {set _ready ok}]
    set timer [after $timeout_ms [namespace code {set _ready timeout}]]
    vwait ::aa::scpi::_ready
    after cancel $timer
    fileevent $chan readable {}
    return $_ready
}

proc ::aa::scpi::_readline {} {
    variable chan; variable async
    if {!$async} {
        set n [gets $chan line]
        if {$n < 0} { error "SCPI: read failed (connection closed?)" }
        return $line
    }
    while 1 {
        set n [gets $chan line]
        if {$n >= 0} { return $line }
        if {[eof $chan]} { error "SCPI: connection closed by instrument" }
        if {[_wait_readable] eq "timeout"} { error "SCPI: read timeout (no reply)" }
    }
}

proc ::aa::scpi::_readn {n} {
    variable chan; variable async
    set data ""
    while {[string length $data] < $n} {
        set want [expr {$n - [string length $data]}]
        append data [read $chan $want]
        if {[string length $data] < $n} {
            if {[eof $chan]} { error "SCPI: connection closed mid-block" }
            if {!$async} { error "SCPI: short block read in sync mode" }
            if {[_wait_readable] eq "timeout"} { error "SCPI: block read timeout" }
        }
    }
    return $data
}

# --------------------------------------------------------------- public API
## write cmd -- send a command or a ';'-separated compound of commands, no reply expected.
proc ::aa::scpi::write {cmd} {
    variable chan; variable connected
    if {!$connected} { error "SCPI: not connected" }
    _log TX $cmd
    puts $chan $cmd
    if {[fconfigure $chan -buffering] ne "none"} { flush $chan }
}

## query cmd -- send cmd (normally ending in '?') and return the one-line reply.
proc ::aa::scpi::query {cmd} {
    write $cmd
    set reply [string trim [_readline]]
    _log RX $reply
    return $reply
}

## query_block cmd -- send cmd and return the payload of an IEEE-488.2
## definite-length arbitrary block reply ("#<ndigits><length><bytes>") as a
## raw Tcl byte string, e.g. for `binary scan ... c*` on waveform data.
proc ::aa::scpi::query_block {cmd} {
    write $cmd
    set hash [_readn 1]
    if {$hash ne "#"} { error "SCPI: expected '#' block header, got [list $hash]" }
    set ndig [_readn 1]
    if {![string is digit -strict $ndig]} { error "SCPI: malformed block header" }
    set len  [_readn $ndig]
    set data [_readn $len]
    catch { _readline }        ;# swallow the line terminator after the block
    _log RX "<binary block, [string length $data] bytes>"
    return $data
}

## check_errors ?query? -- drain the instrument's SCPI error queue (default
## command ":SYSTem:ERRor?"). Raises a Tcl error listing every non-zero entry
## found, so callers can just `check_errors` after a batch of setup commands.
proc ::aa::scpi::check_errors {{errquery ":SYSTem:ERRor?"}} {
    set errs {}
    for {set i 0} {$i < 25} {incr i} {
        set e [query $errquery]
        if {[regexp {^\+?0\s*,} $e] || [string match -nocase {*no error*} $e]} { break }
        lappend errs $e
    }
    if {[llength $errs]} { error "SCPI error(s) reported by instrument: [join $errs {; }]" }
}
