#!/usr/bin/env tclsh
# mockscope.tcl -- fake SCPI scope + signal generator for developing the antenna
# analyzer without hardware.
#
#     tclsh mockscope.tcl ?port?          (default 5025, loopback only)
#
# Line-based SCPI over a raw TCP socket.

package require Tcl 8.6
set PI [expr {acos(-1)}]

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

# ---------------------------------------------------------------- the commands
cmd *IDN {return "MOCK,DSO2000-SIM,0001,0.1"}

proc dispatch {chan line} {
    puts "Recieved: $line\n"
    foreach stmt [split $line ";"] {
	set stmt [string trim $stmt]
	if {$stmt eq ""} continue
	regexp {^(\S+)\s*(.*)$} $stmt -> head arg
	set isq [expr {[string index $head end] eq "?"}]
	set head [string trimright $head ?]
	set hit 0
	foreach {re handler} $::registry {
	    if {[regexp -nocase $re $head -> idx]} {
		set hit 1
    		if {[catch {{*}$handler $isq $idx $arg} reply]} {
		    puts "error\n"
		}
		if {$isq} {puts -nonewline $chan "$reply\n"}
		break
	    }
	}
	if {!$hits} {puts "error"}
    }
}

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
