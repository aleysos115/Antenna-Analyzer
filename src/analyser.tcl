#!/usr/bin/env tclsh

package require Tcl 8.6

namespace eval scpi {
    variable ch
    proc connect {host port} {
	variable ch
	set ch [socket $host $port]
	fconfigure $ch -translation binary -buffering none
    }

    proc write {cmd} {variable ch; puts -nonewline $ch "$cmd\n"}
    proc query {cmd} {variable ch; write $cmd; string trim [gets $ch] }
    proc query_block {cmd} {
	variable ch
	write $cmd
	read $ch 1
	set n   [read $ch 1]
        set len [read $ch $n]
        set data [read $ch $len]
        read $ch 1                              ;# terminator
        return $data
    }

    proc check {} {                             ;# raise if the error queue is not empty
	set e [query :SYSTem:ERRor?]
	if {![string match 0* $e]} { error "SCPI error: $e" }
    }
}

set port [expr {$argc ? [lindex $argv 0] : 5025}]
puts "Connecting to: 127.0.0.1:$port"
scpi::connect 127.0.0.1 $port
puts "IDN: [scpi::query *IDN?]"
