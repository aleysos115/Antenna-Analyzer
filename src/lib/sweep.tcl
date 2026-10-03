#
# sweep.tcl -- orchestrates the driver + dsp + calib layers into the actual
# measurement: one complex ratio H=V2/V1 per frequency, a 3-standard SOL
# calibration, and a calibrated sweep that produces an aa::calib dataset.
#
# Design note -- no Tcl `coroutine`:
#   An earlier sketch of this app ran the sweep inside a `coroutine` so it
#   could `yield` after each point and keep the GUI responsive. Once
#   scpi.tcl's `query`/`query_block` were built on `vwait` (see that file's
#   header), every network wait already re-enters the Tk event loop on its
#   own -- so the sweep can be a plain, easier-to-follow proc, and the GUI
#   stays responsive (redraws, and a Cancel click, land the moment the
#   in-flight query returns) without an extra layer of coroutine bookkeeping.
#   `cancel` below just sets a flag the loop checks between points; the Run
#   button also gets disabled while a sweep is in progress so a second sweep
#   can't be started re-entrantly through the same event-loop re-entry.
#
# Depends on: complex.tcl, dsp.tcl, calib.tcl, driver.tcl
#
namespace eval ::aa::sweep {
    variable cancel_flag 0
    variable cal {}                 ;# dict: freq -> {Ms Mo Ml}, from calibrate_build
    variable settings
    array set settings {
        rs         50.0
        z0         50.0
        amplitude  1.0
        cycles     15
        ch1_scale  0.2
        ch2_scale  0.2
        ch1_probe  1
        ch2_probe  1
        coupling   DC
    }
    namespace export configure cancel reset_cancel have_calibration clear_calibration \
                      measure_h measure_standard calibrate_build run linspace
}

## configure args -- update one or more settings, e.g.
##   ::aa::sweep::configure rs 51.3 amplitude 0.5
proc ::aa::sweep::configure {args} {
    variable settings
    foreach {k v} $args {
        if {![info exists settings($k)]} { error "sweep: unknown setting '$k'" }
        set settings($k) $v
    }
}
proc ::aa::sweep::get {k} { variable settings; return $settings($k) }

proc ::aa::sweep::cancel       {} { variable cancel_flag; set cancel_flag 1 }
proc ::aa::sweep::reset_cancel {} { variable cancel_flag; set cancel_flag 0 }

proc ::aa::sweep::have_calibration {} { variable cal; expr {[dict size $cal] > 0} }
proc ::aa::sweep::clear_calibration {} { variable cal; set cal {} }

## linspace lo hi n -- n frequencies from lo to hi Hz inclusive, ascending.
proc ::aa::sweep::linspace {lo hi n} {
    if {$n <= 1} { return [list $lo] }
    set out {}
    set step [expr {($hi-$lo)/double($n-1)}]
    for {set i 0} {$i < $n} {incr i} { lappend out [expr {$lo + $i*$step}] }
    return $out
}

## measure_h f -- one calibration-free measurement at frequency f (Hz).
## Configures the source/timebase, triggers a single acquisition, downloads
## both channels, and returns the complex ratio H = V2/V1 via a matched
## single-bin DFT (dsp::phasor) on each channel.
proc ::aa::sweep::measure_h {f} {
    variable settings
    ::aa::driver::acquire $f [expr {$settings(cycles)/double($f)/12.0}]
    lassign [::aa::driver::read_channel 1] dt1 y1
    lassign [::aa::driver::read_channel 2] dt2 y2
    set fs [expr {1.0/$dt1}]
    set p1 [::aa::dsp::phasor $y1 $fs $f]
    set p2 [::aa::dsp::phasor $y2 $fs $f]
    ::aa::complex::cdiv $p2 $p1
}

## measure_standard freqs statuscb -- sweep measure_h across freqs and return
## a dict {freq -> H}. statuscb, if non-empty, is called as
## "{*}$statuscb $doneCount $total $f" after every point (progress reporting;
## it may safely touch the GUI, since this loop runs on the main thread and
## between-point code -- not inside a query -- is where we're called back).
## Honors ::aa::sweep::cancel: returns whatever was collected so far.
proc ::aa::sweep::measure_standard {freqs {statuscb {}}} {
    variable cancel_flag
    set out [dict create]
    set n [llength $freqs]
    set i 0
    foreach f $freqs {
        if {$cancel_flag} break
        dict set out $f [measure_h $f]
        incr i
        if {$statuscb ne ""} { uplevel #0 [list {*}$statuscb $i $n $f] }
    }
    return $out
}

## calibrate_build freqs shortD openD loadD -- combine three per-frequency
## measure_standard results (for SHORT/OPEN/LOAD) into the calibration dict
## used by `run`. Stores it in the module and also returns it.
proc ::aa::sweep::calibrate_build {freqs shortD openD loadD} {
    variable cal
    set cal [dict create]
    foreach f $freqs {
        if {![dict exists $shortD $f] || ![dict exists $openD $f] || ![dict exists $loadD $f]} {
            error "sweep: missing calibration point at [expr {$f/1e6}] MHz"
        }
        dict set cal $f [list [dict get $shortD $f] [dict get $openD $f] [dict get $loadD $f]]
    }
    return $cal
}

## run freqs statuscb -- the calibrated measurement sweep. Returns a
## dict with keys "ok" (1 if it ran to completion, 0 if cancelled) and
## "dataset" (an aa::calib dataset, see calib.tcl). Frequencies with no
## matching calibration point are corrected as 2H-1 (equivalent to an ideal,
## lossless bridge with no channel errors) rather than skipped, so a sweep
## started without calibrating still produces a usable, if less accurate,
## trace -- the GUI flags this in the status bar.
proc ::aa::sweep::run {freqs {statuscb {}}} {
    variable cancel_flag; variable cal
    set cancel_flag 0
    set ds [::aa::calib::new_dataset]
    set n [llength $freqs]
    set i 0
    foreach f $freqs {
        if {$cancel_flag} break
        set H [measure_h $f]
        if {[dict exists $cal $f]} {
            lassign [dict get $cal $f] Ms Mo Ml
            set g [::aa::calib::sol_correct $H $Ms $Mo $Ml]
        } else {
            set g [::aa::complex::csub [::aa::complex::cmul {2 0} $H] {1 0}]
        }
        ::aa::calib::add_point ds $f $g
        incr i
        if {$statuscb ne ""} { uplevel #0 [list {*}$statuscb $i $n $f $g] }
    }
    dict create ok [expr {!$cancel_flag}] dataset $ds
}
