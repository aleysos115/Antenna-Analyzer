#!/usr/bin/env tclsh
# mockscope.tcl -- fake SCPI scope + signal generator for developing the antenna
# analyzer without hardware.
#
#     tclsh mockscope.tcl ?port?          (default 5025, loopback only)
#
# Line-based SCPI over a raw TCP socket.  The mnemonics are PLACEHOLDERS in a
# generic SCPI style: replace them with the ones from your scope's programmer's
# manual (and keep the real driver and this mock in sync).
#
# The mock also has a few :SIMulate commands that a real instrument would never
# have.  They are the "back door" used to change what is connected to the test
# port and to ask what the true reflection coefficient is.

package require Tcl 8.6
set PI [expr {acos(-1)}]

# ------------------------------------------------------------------ state
# freq [Hz], amp [Vpp], out 0/1        | tbase [s/div], npts (record length)
# scaleN [V/div], probeN, coupN        | dut: SHORT OPEN LOAD ANT
# Imperfections the calibration has to remove: gain2, skew [s], cstray [F]
# noise = ADC noise in LSB rms
array set S0 {
    freq 1e6  amp 1.0  out 0
    tbase 1e-6  npts 4096
    scale1 0.2  scale2 0.2  probe1 1  probe2 1  coup1 DC  coup2 DC
    wsrc 1  dut LOAD  Rs 50.0
    gain2 0.97  skew 2e-9  cstray 5e-12  noise 1.0
}
array set S [array get S0]
set errq {}
array set acq {}

proc err {code msg} { lappend ::errq [list $code $msg] }

# Validate + store a numeric parameter (pushes standard SCPI errors on failure)
proc setnum {var arg lo hi} {
    if {![string is double -strict $arg]} { err -104 "Data type error";  return }
    if {$arg < $lo || $arg > $hi}         { err -222 "Data out of range"; return }
    set ::S($var) $arg
}

# ------------------------------------------------------- SCPI command registry
# ":CHANnel#:SCALe" -> ^:?(?:CHAN|CHANNEL)(\d+):(?:SCAL|SCALE)$   (matched -nocase)
# i.e. each node may be written in its short form (capitals) or its long form.
proc esc {s} { regsub -all {\W} $s {\\&} }
proc pattern2re {pat} {
    set parts {}
    foreach node [split [string trimleft $pat :] :] {
        set idx ""
        if {[string index $node end] eq "#"} {
            set node [string range $node 0 end-1]
            set idx {(\d+)}
        }
        set short [regsub -all {[a-z]} $node ""]
        lappend parts "(?:[esc $short]|[esc [string toupper $node]])$idx"
    }
    return "^:?[join $parts :]\$"
}

set registry {}
proc cmd {pattern body} {
    lappend ::registry [pattern2re $pattern] [list apply [list {isq idx arg} $body]]
}

proc dispatch {chan line} {
    foreach stmt [split $line ";"] {           ;# several commands per line
        set stmt [string trim $stmt]
        if {$stmt eq ""} continue
        regexp {^(\S+)\s*(.*)$} $stmt -> head arg
        set isq  [expr {[string index $head end] eq "?"}]
        set head [string trimright $head ?]
        set hit 0
        foreach {re handler} $::registry {
            if {[regexp -nocase $re $head -> idx]} {
                set hit 1
                if {[catch {{*}$handler $isq $idx $arg} reply]} {
                    err -300 "Device-specific error: $reply"
                    set reply ""
                }
                if {$isq} { puts -nonewline $chan "$reply\n" }
                break
            }
        }
        if {!$hit} { err -113 "Undefined header: $head" }
    }
}

# ------------------------------------------------------ physics of the test head
#   AWG --+--[Rs]--+-- DUT          CH1 = source side, CH2 = DUT side
#         CH1      CH2             H = V2/V1 = 1 / (1 + Rs*Y_dut)
proc antenna_Z {f} {                            ;# series RLC "antenna", ~7.1 MHz
    set w [expr {2*$::PI*$f}]
    list 35.0 [expr {$w*2.2e-6 - 1/($w*228e-12)}]
}
proc dut_gamma {f} {                            ;# true reflection coefficient {re im}
    switch $::S(dut) {
        SHORT { return {-1.0 0.0} }
        OPEN  { return {1.0 0.0} }
        LOAD  { return {0.0 0.0} }
        ANT   {
            lassign [antenna_Z $f] R X
            set den [expr {($R+50)**2 + $X*$X}]
            return [list [expr {($R*$R - 2500 + $X*$X)/$den}] [expr {100*$X/$den}]]
        }
    }
}
proc dut_H {f} {                                ;# {re im} of V2/V1, stray C included
    set bC [expr {2*$::PI*$f*$::S(cstray)}]
    switch $::S(dut) {
        SHORT { return {0.0 0.0} }
        OPEN  { set g 0.0;  set b $bC }
        LOAD  { set g 0.02; set b $bC }
        ANT   {
            lassign [antenna_Z $f] R X
            set n [expr {$R*$R + $X*$X}]
            set g [expr {$R/$n}]; set b [expr {$bC - $X/$n}]
        }
    }
    set a [expr {1 + $::S(Rs)*$g}]; set c [expr {$::S(Rs)*$b}]
    set den [expr {$a*$a + $c*$c}]
    list [expr {$a/$den}] [expr {-$c/$den}]
}

proc gauss {} { expr {sqrt(-2*log(1-rand()))*cos(2*$::PI*rand())} }
proc adc {v ch} {                               ;# volts -> signed 8-bit code, 25 codes/div
    set lsb [expr {$::S(scale$ch)/25.0}]
    expr {max(-127, min(127, round($v/$lsb + $::S(noise)*[gauss])))}
}

proc acquire {} {                               ;# fill acq(1), acq(2), acq(dt)
    set f $::S(freq);  set w [expr {2*$::PI*$f}]
    set A [expr {$::S(out) ? $::S(amp)/2.0 : 0.0}]
    lassign [dut_H $f] hr hi
    set mag [expr {$::S(gain2)*hypot($hr,$hi)}]              ;# CH2 gain error
    set ph  [expr {atan2($hi,$hr) - $w*$::S(skew)}]          ;# CH2 skew
    set phi0 [expr {2*$::PI*rand()}]                         ;# AWG not locked to scope
    set N  $::S(npts)
    set dt [expr {max(1e-9, 12*$::S(tbase)/$N)}]             ;# 12 div, 1 GSa/s max
    set y1 {}; set y2 {}
    for {set n 0} {$n < $N} {incr n} {
        set th [expr {$w*$n*$dt + $phi0}]
        lappend y1 [adc [expr {$A*cos($th)}] 1]
        lappend y2 [adc [expr {$A*$mag*cos($th+$ph)}] 2]
    }
    array set ::acq [list dt $dt 1 $y1 2 $y2]
}

# ---------------------------------------------------------------- the commands
cmd *IDN {return "MOCK,DSO2000-SIM,0001,0.1"}
cmd *RST {set d $::S(dut); array unset ::S; array set ::S [array get ::S0]; set ::S(dut) $d}
cmd *CLS {set ::errq {}}
cmd *OPC {return 1}
cmd :SYSTem:ERRor {
    if {![llength $::errq]} { return {0,"No error"} }
    lassign [lindex $::errq 0] c m
    set ::errq [lrange $::errq 1 end]
    return "$c,\"$m\""
}

cmd :SOURce:FREQuency {if {$isq} {return $::S(freq)}; setnum freq $arg 1 25e6}
cmd :SOURce:AMPLitude {if {$isq} {return $::S(amp)};  setnum amp  $arg 0.002 5}
cmd :SOURce:OUTPut    {
    if {$isq} {return $::S(out)}
    set ::S(out) [expr {[string toupper $arg] in {1 ON} ? 1 : 0}]
}

cmd :CHANnel#:SCALe    {if {$isq} {return $::S(scale$idx)}; setnum scale$idx $arg 1e-3 10}
cmd :CHANnel#:PROBe    {if {$isq} {return $::S(probe$idx)}; setnum probe$idx $arg 1 1000}
cmd :CHANnel#:COUPling {if {$isq} {return $::S(coup$idx)};  set ::S(coup$idx) [string toupper $arg]}
cmd :TIMebase:SCALe    {if {$isq} {return $::S(tbase)};     setnum tbase $arg 1e-9 50}

cmd :SINGle {acquire}
cmd :STOP   {}
cmd :RUN    {}

cmd :WAVeform:SOURce   {if {$isq} {return $::S(wsrc)}; set ::S(wsrc) [string index $arg end]}
cmd :WAVeform:PREamble {                        ;# dt, points, volts-per-code
    if {![info exists ::acq(dt)]} { err -230 "Data corrupt or stale"; return }
    set ch $::S(wsrc)
    return "$::acq(dt),[llength $::acq($ch)],[expr {$::S(scale$ch)/25.0}]"
}
cmd :WAVeform:DATA {                            ;# IEEE 488.2 definite-length block
    if {![info exists ::acq(dt)]} { err -230 "Data corrupt or stale"; return "#10" }
    set blk [binary format c* $::acq($::S(wsrc))]
    set n [string length $blk]
    return "#[string length $n]$n$blk"
}

# back door (not part of any real instrument)
cmd :SIMulate:DUT {
    if {$isq} {return $::S(dut)}
    set v [string toupper $arg]
    if {$v ni {SHORT OPEN LOAD ANT}} { err -224 "Illegal parameter value"; return }
    set ::S(dut) $v
}
cmd :SIMulate:GAMMa {lassign [dut_gamma $::S(freq)] re im; return "$re,$im"}

# --------------------------------------------------------------- server plumbing
# Replies are built in a big buffer and flushed once, so each reply leaves as one
# TCP write.  (With the default 4 KB buffer, a 4 KB waveform is split in two
# writes and the second one can stall ~40 ms on Nagle + delayed-ACK.)
proc accept {chan addr port} {
    fconfigure $chan -translation binary -buffering full -buffersize 1000000 -blocking 0
    fileevent $chan readable [list onread $chan]
}
proc onread {chan} {
    if {[catch {
        while {[gets $chan line] >= 0} { dispatch $chan [string trim $line] }
        if {[eof $chan]} { close $chan } else { flush $chan }
    }]} { catch {close $chan} }
}

set port [expr {$argc ? [lindex $argv 0] : 5025}]
set srv  [socket -server accept -myaddr 127.0.0.1 $port]
puts "mockscope listening on 127.0.0.1:[lindex [fconfigure $srv -sockname] 2]"
vwait forever
