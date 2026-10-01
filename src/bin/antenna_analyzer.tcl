#!/usr/bin/env wish
#
# antenna_analyzer.tcl -- launch the GUI.
#     wish bin/antenna_analyzer.tcl
#
package require Tk

set ::topdir [file dirname [file dirname [file normalize [info script]]]]
source [file join $::topdir lib   all.tcl]
source [file join $::topdir gui   smith.tcl]
source [file join $::topdir gui   plot.tcl]
source [file join $::topdir gui   app.tcl]

::aa::gui::main
