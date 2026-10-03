#
# driver.tcl -- semantic instrument operations (set_freq, read_channel, ...)
# built on top of lib/scpi.tcl's write/query/query_block.
#
# Every literal SCPI mnemonic the app sends lives in one place: the
# `profile` array below. It currently holds *generic placeholder* commands
# that match mock/mockscope.tcl and are written in the generic SCPI style
# the DSO2000 family documents (:SOURce:FREQuency, :WAVeform:DATA?, and so
# on). Before pointing this at real hardware, open your scope's programmer's
# manual, diff its command set against this array, and edit the strings
# below -- nothing else in the app needs to change. See
# docs/scpi_reference.rst.
#
# Depends on: scpi.tcl
#
namespace eval ::aa::driver {
    variable profile
    array set profile {
        idn                 *IDN?
        reset               *RST
        clear               *CLS
        opc_query           *OPC?
        err_query           :SYSTem:ERRor?
        src_freq_set        {:SOURce:FREQuency %s}
        src_freq_query      :SOURce:FREQuency?
        src_ampl_set        {:SOURce:AMPLitude %s}
        src_out_set         {:SOURce:OUTPut %s}
        chan_scale_set      {:CHANnel%d:SCALe %s}
        chan_probe_set      {:CHANnel%d:PROBe %s}
        chan_coupling_set   {:CHANnel%d:COUPling %s}
        tbase_scale_set     {:TIMebase:SCALe %s}
        acquire_single      :SINGle
        wav_source_set      {:WAVeform:SOURce CHANnel%d}
        wav_preamble_query  :WAVeform:PREamble?
        wav_data_query      :WAVeform:DATA?
    }

    namespace export idn reset configure_source configure_channel \
                      set_timebase single_and_wait read_channel load_profile
}

## load_profile dict -- overlay replacement mnemonics onto the default
## profile, e.g. after reading a JSON/Tcl-dict file shipped for a specific
## instrument. Unknown keys are rejected so a typo doesn't silently do nothing.
proc ::aa::driver::load_profile {overrides} {
    variable profile
    foreach {k v} $overrides {
        if {![info exists profile($k)]} { error "driver: unknown profile key '$k'" }
        set profile($k) $v
    }
}

proc ::aa::driver::_cmd {key args} {
    variable profile
    format $profile($key) {*}$args
}

## idn -- return the instrument's *IDN? response
proc ::aa::driver::idn {} { ::aa::scpi::query [_cmd idn] }

## reset -- send *RST;*CLS
proc ::aa::driver::reset {} {
    ::aa::scpi::write [_cmd reset]
    ::aa::scpi::write [_cmd clear]
}

## configure_source amplitude_vpp on -- set the built-in generator's amplitude
## and output state (frequency is set per-point by set_freq, below).
proc ::aa::driver::configure_source {amplitude_vpp on} {
    ::aa::scpi::write [_cmd src_ampl_set $amplitude_vpp]
    ::aa::scpi::write [_cmd src_out_set [expr {$on ? "ON" : "OFF"}]]
}

## set_freq hz -- set the generator frequency for the next acquisition
proc ::aa::driver::set_freq {hz} { ::aa::scpi::write [_cmd src_freq_set $hz] }

## acquire hz s_per_div -- set frequency + timebase and trigger one
## acquisition, waiting for it to finish. Sent as a single compound SCPI
## line (one round trip, one *OPC? reply) rather than three separate writes
## and a query: on a loopback or LAN socket each unacknowledged small write
## is a fresh TCP segment, and without Nagle disabled (plain Tcl sockets
## have no portable way to set TCP_NODELAY) a run of them can each stall
## for a delayed-ACK interval. Compounding is also simply how SCPI is meant
## to be driven -- see sweep.tcl's design note and docs/scpi_reference.rst.
proc ::aa::driver::acquire {hz s_per_div} {
    set line [join [list [_cmd src_freq_set $hz] [_cmd tbase_scale_set $s_per_div] \
                        [_cmd acquire_single] [_cmd opc_query]] {;}]
    ::aa::scpi::query $line
}

## configure_channel ch scale probe coupling -- vertical setup for CH1/CH2
proc ::aa::driver::configure_channel {ch scale probe coupling} {
    ::aa::scpi::write [_cmd chan_scale_set $ch $scale]
    ::aa::scpi::write [_cmd chan_probe_set $ch $probe]
    ::aa::scpi::write [_cmd chan_coupling_set $ch $coupling]
}

## set_timebase s_per_div -- horizontal scale
proc ::aa::driver::set_timebase {s_per_div} { ::aa::scpi::write [_cmd tbase_scale_set $s_per_div] }

## single_and_wait -- trigger one acquisition and block (Tk-safely, see
## scpi.tcl) until it completes, using *OPC? as the synchronization point.
proc ::aa::driver::single_and_wait {} {
    ::aa::scpi::write [_cmd acquire_single]
    ::aa::scpi::query [_cmd opc_query]
}

## read_channel ch -- download one channel's most recent acquisition.
## Returns {dt_seconds samples} where samples is a list of signed integer
## ADC codes (the caller applies volts/code itself if absolute volts matter;
## the phasor extraction in dsp.tcl only needs a signal proportional to volts).
proc ::aa::driver::read_channel {ch} {
    set pre [::aa::scpi::query [join [list [_cmd wav_source_set $ch] [_cmd wav_preamble_query]] {;}]]
    lassign [split $pre ,] dt npts voltsPerCode
    set raw [::aa::scpi::query_block [_cmd wav_data_query]]
    binary scan $raw c* samples
    if {[llength $samples] != $npts} {
        error "driver: CH$ch waveform length mismatch (preamble said $npts, got [llength $samples])"
    }
    list $dt $samples
}
