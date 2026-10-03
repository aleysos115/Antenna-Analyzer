#
# dsp.tcl -- turns a captured waveform into the complex amplitude of one
# frequency component ("software lock-in").  This is what lets the analyzer
# recover amplitude *and phase* from two scope channels instead of relying
# on the scope's own (amplitude-only) measurements.
#
# Depends on: complex.tcl
#
namespace eval ::aa::dsp {
    namespace export phasor mean hann_window
}

## mean y -- arithmetic mean of a list of numbers
proc ::aa::dsp::mean {y} {
    set n [llength $y]
    if {$n == 0} { return 0.0 }
    expr {double([::tcl::mathop::+ {*}$y]) / $n}
}

## hann_window n N -- Hann window weight for sample index n of N (0 <= n < N)
proc ::aa::dsp::hann_window {n N} {
    expr {0.5 - 0.5*cos(2*acos(-1)*$n/$N)}
}

## phasor y fs f
#
# Correlate a real-valued sample sequence y (sampled at fs Hz) against a
# complex exponential at frequency f, i.e. compute one bin of the DFT with a
# Hann window applied.  Returns {re im} of the resulting phasor.
#
# This is equivalent to (and far cheaper than) fitting f to a windowed FFT
# and reading off one bin: it costs O(N) instead of O(N log N) and needs no
# fixed record length or power-of-two size, which matters because the
# generator frequency and the scope's sample rate are not synchronized.
#
# The signal's DC component is removed first so that trigger offset, probe
# offset, or an imperfect null on channel 2 do not leak into the bin.
#
proc ::aa::dsp::phasor {y fs f} {
    set N [llength $y]
    if {$N < 4} { error "phasor: need at least 4 samples, got $N" }
    set mu [mean $y]
    set w  [expr {2*acos(-1)*$f/$fs}]
    set re 0.0
    set im 0.0
    set n 0
    foreach v $y {
        set x [expr {[hann_window $n $N]*($v-$mu)}]
        set re [expr {$re + $x*cos($w*$n)}]
        set im [expr {$im - $x*sin($w*$n)}]
        incr n
    }
    list $re $im
}
