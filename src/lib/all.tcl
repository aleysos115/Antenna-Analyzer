#
# all.tcl -- source every lib/ module in dependency order. Entry points
# (bin/antenna_analyzer.tcl, tests/*.tcl) do just:
#     source [file join $libdir all.tcl]
#
namespace eval ::aa {}
set ::aa::libdir [file dirname [file normalize [info script]]]

foreach f {complex.tcl dsp.tcl calib.tcl scpi.tcl driver.tcl sweep.tcl} {
    source [file join $::aa::libdir $f]
}
