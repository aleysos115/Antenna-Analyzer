#!/usr/bin/env tclsh
# mock_selftest.tcl -- starts mock/mockscope.tcl and exercises the real
# lib/ code (not a copy of it) end to end: connect, SOL-calibrate, sweep an
# "antenna", and compare the calibrated Gamma against the mock's known truth
# (exposed only through its :SIMulate:GAMMa? back door).
#
#     tclsh tests/mock_selftest.tcl        (exit 0 = pass)
#
package require Tcl 8.6
set ::topdir [file dirname [file dirname [file normalize [info script]]]]
source [file join $::topdir lib all.tcl]

set port 5099
set pid [exec tclsh [file join $::topdir mock mockscope.tcl] $port > /dev/null &]
after 400

aa::scpi::connect_tcp 127.0.0.1 $port
puts "IDN: [aa::driver::idn]"

# --- error-queue behaviour, same as a real instrument's ---
aa::scpi::write "*CLS"
aa::scpi::write ":SOURce:FREQuency 30e6"     ;# out of range on purpose
aa::scpi::write ":BOGUS:COMMAND"
if {[catch {aa::scpi::check_errors} msg]} {
    puts "check_errors correctly raised: $msg"
} else {
    puts "FAIL: check_errors should have raised on the errors above"
    exit 1
}

# --- configure ---
aa::driver::reset
aa::driver::configure_source 1.0 1
aa::driver::configure_channel 1 0.2 1 DC
aa::driver::configure_channel 2 0.2 1 DC
aa::scpi::check_errors

set freqs [aa::sweep::linspace 2e6 25e6 24]

# --- calibrate ---
aa::scpi::write ":SIMulate:DUT SHORT"
set shortD [aa::sweep::measure_standard $freqs]
aa::scpi::write ":SIMulate:DUT OPEN"
set openD  [aa::sweep::measure_standard $freqs]
aa::scpi::write ":SIMulate:DUT LOAD"
set loadD  [aa::sweep::measure_standard $freqs]
aa::sweep::calibrate_build $freqs $shortD $openD $loadD

if {![aa::sweep::have_calibration]} { puts "FAIL: no calibration stored"; exit 1 }

# --- sweep the simulated antenna and compare to ground truth ---
aa::scpi::write ":SIMulate:DUT ANT"
set result [aa::sweep::run $freqs]
if {![dict get $result ok]} { puts "FAIL: sweep reported cancelled"; exit 1 }
set ds [dict get $result dataset]

set worst 0.0
puts [format "%6s %9s %9s" MHz SWR_true SWR_cal]
foreach f [dict get $ds freqs] g [dict get $ds gamma] {
    aa::scpi::write ":SOURce:FREQuency $f"
    lassign [split [aa::scpi::query ":SIMulate:GAMMa?"] ,] tr ti
    set e [aa::complex::cabs [aa::complex::csub $g [list $tr $ti]]]
    if {$e > $worst} { set worst $e }
    if {int($f/1e6) % 3 == 2} {
        puts [format "%6.1f %9.3f %9.3f" [expr {$f/1e6}] \
                  [aa::calib::swr_of_gamma [list $tr $ti]] [aa::calib::swr_of_gamma $g]]
    }
}
aa::scpi::check_errors
puts [format "max |Gamma error| vs ground truth: %.4f" $worst]

# --- export smoke test ---
aa::calib::write_s1p /tmp/aa_selftest.s1p $ds
aa::calib::write_csv /tmp/aa_selftest.csv $ds
puts "wrote [file size /tmp/aa_selftest.s1p] bytes to /tmp/aa_selftest.s1p"

aa::scpi::disconnect
catch {exec kill $pid}

if {$worst < 0.01} { puts PASS; exit 0 } else { puts FAIL; exit 1 }
