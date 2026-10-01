#
# app.tcl -- the Tk GUI. Everything in here is orchestration: it calls into
# aa::scpi / aa::driver / aa::sweep / aa::calib for all the real work and
# aa::gui::smith / aa::gui::plot for all the drawing. Call ::aa::gui::main
# once, after sourcing lib/all.tcl, gui/smith.tcl and gui/plot.tcl.
#
namespace eval ::aa::gui {
    variable w                 ;# widget path array
    variable v                 ;# form/state variable array (see defaults below)
    variable current_dataset {}
    variable live_freqs {}
    variable live_gammas {}

    array set v {
        transport   TCP
        host        127.0.0.1
        port        5025
        device      /dev/usbtmc0
        conn_text   "Disconnected"
        conn_color  #b3261e
        idn         ""
        start_mhz   1.8
        stop_mhz    30.0
        points      51
        amplitude   1.0
        rs          50.0
        z0          50.0
        cycles      15
        ch1_scale   0.2
        ch2_scale   0.2
        ch1_probe   1
        ch2_probe   1
        coupling    DC
        cal_status  "Not calibrated"
        status      "Ready."
        readout     ""
        cmdline     ""
    }
}

# --------------------------------------------------------------- top-level UI
proc ::aa::gui::main {} {
    variable w; variable v
    wm title . "Tcl/Tk Antenna Analyzer"
    wm minsize . 900 600

    build_menu
    build_connection_bar
    build_notebook
    build_statusbar

    grid .top    -row 0 -column 0 -sticky ew
    grid .nb     -row 1 -column 0 -sticky nsew
    grid .status -row 2 -column 0 -sticky ew
    grid rowconfigure . 1 -weight 1
    grid columnconfigure . 0 -weight 1

    on_transport_change
    aa::scpi::set_log_callback ::aa::gui::console_log
    redraw_all [dict create freqs {} gamma {}]
}

proc ::aa::gui::build_menu {} {
    variable w
    set m [menu .menubar -tearoff 0]
    . configure -menu $m
    set filem [menu $m.file -tearoff 0]
    $m add cascade -label File -menu $filem -underline 0
    $filem add command -label "Export CSV..." -command ::aa::gui::do_export_csv
    $filem add command -label "Export Touchstone (.s1p)..." -command ::aa::gui::do_export_s1p
    $filem add separator
    $filem add command -label Quit -command exit

    set instm [menu $m.inst -tearoff 0]
    $m add cascade -label Instrument -menu $instm -underline 0
    $instm add command -label "Reset (*RST)" -command ::aa::gui::do_reset
    $instm add command -label "Query *IDN?" -command ::aa::gui::do_query_idn

    set helpm [menu $m.help -tearoff 0]
    $m add cascade -label Help -menu $helpm -underline 0
    $helpm add command -label About -command ::aa::gui::show_about
}

# ------------------------------------------------------------ connection bar
proc ::aa::gui::build_connection_bar {} {
    variable v
    ttk::frame .top -padding {8 6}
    ttk::label .top.transport_l -text "Transport:"
    ttk::combobox .top.transport -textvariable ::aa::gui::v(transport) \
        -values {TCP USBTMC} -state readonly -width 8
    bind .top.transport <<ComboboxSelected>> ::aa::gui::on_transport_change

    ttk::label .top.host_l -text "Host:"
    ttk::entry .top.host -textvariable ::aa::gui::v(host) -width 14
    ttk::label .top.port_l -text "Port:"
    ttk::entry .top.port -textvariable ::aa::gui::v(port) -width 6
    ttk::label .top.dev_l -text "Device:"
    ttk::entry .top.dev -textvariable ::aa::gui::v(device) -width 16

    ttk::button .top.connect -text Connect -command ::aa::gui::do_connect -width 10

    label .top.led -textvariable ::aa::gui::v(dot) -fg #b3261e -font {Helvetica 12 bold}
    set ::aa::gui::v(dot) "\u25CF"
    ttk::label .top.connlabel -textvariable ::aa::gui::v(conn_text)
    ttk::label .top.idnlabel -textvariable ::aa::gui::v(idn) -foreground #55606b

    pack .top.transport_l -side left
    pack .top.transport -side left -padx {2 10}
    pack .top.host_l -side left
    pack .top.host -side left -padx {2 10}
    pack .top.port_l -side left
    pack .top.port -side left -padx {2 10}
    pack .top.dev_l -side left
    pack .top.dev -side left -padx {2 10}
    pack .top.connect -side left -padx {4 10}
    pack .top.led -side left
    pack .top.connlabel -side left -padx {2 14}
    pack .top.idnlabel -side left
}

proc ::aa::gui::on_transport_change {} {
    variable v
    if {$v(transport) eq "TCP"} {
        foreach wd {.top.host_l .top.host .top.port_l .top.port} { $wd configure -state normal }
        .top.dev configure -state disabled
    } else {
        foreach wd {.top.host_l .top.host .top.port_l .top.port} { $wd configure -state disabled }
        .top.dev configure -state normal
    }
}

proc ::aa::gui::set_connected_ui {ok} {
    variable v
    if {$ok} {
        set v(dot) "\u25CF"; .top.led configure -fg #1e8e3e
        set v(conn_text) "Connected"
    } else {
        set v(dot) "\u25CF"; .top.led configure -fg #b3261e
        set v(conn_text) "Disconnected"
        set v(idn) ""
    }
}

proc ::aa::gui::do_connect {} {
    variable v
    if {[aa::scpi::connected]} {
        aa::scpi::disconnect
        set_connected_ui 0
        .top.connect configure -text Connect
        set v(status) "Disconnected."
        return
    }
    if {[catch {
        if {$v(transport) eq "TCP"} {
            aa::scpi::connect_tcp $v(host) $v(port)
        } else {
            aa::scpi::connect_usbtmc $v(device)
        }
        set v(idn) [aa::driver::idn]
    } err]} {
        tk_messageBox -icon error -title "Connection failed" -message $err
        aa::scpi::disconnect
        set_connected_ui 0
        return
    }
    set_connected_ui 1
    .top.connect configure -text Disconnect
    set v(status) "Connected. $v(idn)"
}

proc ::aa::gui::do_reset {} {
    if {![aa::scpi::connected]} { tk_messageBox -icon error -message "Not connected."; return }
    catch { aa::driver::reset }
    set ::aa::gui::v(status) "Instrument reset."
}
proc ::aa::gui::do_query_idn {} {
    if {![aa::scpi::connected]} { tk_messageBox -icon error -message "Not connected."; return }
    if {[catch { set id [aa::driver::idn] } err]} { tk_messageBox -icon error -message $err; return }
    set ::aa::gui::v(idn) $id
    tk_messageBox -icon info -message $id
}
proc ::aa::gui::show_about {} {
    tk_messageBox -icon info -title "About" -message \
        "Tcl/Tk Antenna Analyzer\n\nA two-channel-scope-plus-generator vector\nreflection analyzer, driven entirely over SCPI.\n\nSee the bundled documentation for architecture,\nschematics, and usage."
}

# -------------------------------------------------------------------- tabs
proc ::aa::gui::build_notebook {} {
    ttk::notebook .nb
    build_sweep_tab
    build_smith_tab
    build_chart_tab
    build_data_tab
    build_console_tab
    .nb add .nb.sweep   -text "Sweep"
    .nb add .nb.smith   -text "Smith Chart"
    .nb add .nb.chart   -text "SWR / Return Loss"
    .nb add .nb.data    -text "Data"
    .nb add .nb.console -text "SCPI Console"
}

# --- Sweep tab -------------------------------------------------------------
proc ::aa::gui::build_sweep_tab {} {
    variable w
    ttk::frame .nb.sweep -padding 10

    ttk::labelframe .nb.sweep.range -text "Sweep range" -padding 8
    grid [ttk::label .nb.sweep.range.l1 -text "Start (MHz)"] -row 0 -column 0 -sticky w -pady 2
    grid [ttk::entry .nb.sweep.range.start -textvariable ::aa::gui::v(start_mhz) -width 8] -row 0 -column 1 -sticky w
    grid [ttk::label .nb.sweep.range.l2 -text "Stop (MHz)"] -row 0 -column 2 -sticky w -padx {12 0}
    grid [ttk::entry .nb.sweep.range.stop -textvariable ::aa::gui::v(stop_mhz) -width 8] -row 0 -column 3 -sticky w
    grid [ttk::label .nb.sweep.range.l3 -text "Points"] -row 0 -column 4 -sticky w -padx {12 0}
    grid [ttk::spinbox .nb.sweep.range.pts -textvariable ::aa::gui::v(points) -width 6 -from 2 -to 2001] \
        -row 0 -column 5 -sticky w
    grid [ttk::label .nb.sweep.range.est -textvariable ::aa::gui::v(time_est) -foreground #55606b] \
        -row 1 -column 0 -columnspan 6 -sticky w -pady {6 0}
    foreach ev {start stop pts} { bind .nb.sweep.range.$ev <KeyRelease> ::aa::gui::update_time_estimate }

    ttk::labelframe .nb.sweep.src -text "Source / test head" -padding 8
    grid [ttk::label .nb.sweep.src.l1 -text "Amplitude (Vpp)"] -row 0 -column 0 -sticky w
    grid [ttk::entry .nb.sweep.src.amp -textvariable ::aa::gui::v(amplitude) -width 7] -row 0 -column 1 -sticky w
    grid [ttk::label .nb.sweep.src.l2 -text "Series R (ohm)"] -row 0 -column 2 -sticky w -padx {12 0}
    grid [ttk::entry .nb.sweep.src.rs -textvariable ::aa::gui::v(rs) -width 7] -row 0 -column 3 -sticky w
    grid [ttk::label .nb.sweep.src.l3 -text "Z0 (ohm)"] -row 0 -column 4 -sticky w -padx {12 0}
    grid [ttk::entry .nb.sweep.src.z0 -textvariable ::aa::gui::v(z0) -width 7] -row 0 -column 5 -sticky w
    grid [ttk::label .nb.sweep.src.l4 -text "Cycles/capture"] -row 1 -column 0 -sticky w -pady {4 0}
    grid [ttk::entry .nb.sweep.src.cyc -textvariable ::aa::gui::v(cycles) -width 7] -row 1 -column 1 -sticky w -pady {4 0}

    ttk::labelframe .nb.sweep.ch -text "Scope channels" -padding 8
    grid [ttk::label .nb.sweep.ch.h1 -text ""] -row 0 -column 0
    grid [ttk::label .nb.sweep.ch.h2 -text "Scale (V/div)"] -row 0 -column 1
    grid [ttk::label .nb.sweep.ch.h3 -text "Probe"] -row 0 -column 2
    grid [ttk::label .nb.sweep.ch.r1 -text "CH1 (source)"] -row 1 -column 0 -sticky w
    grid [ttk::entry .nb.sweep.ch.s1 -textvariable ::aa::gui::v(ch1_scale) -width 7] -row 1 -column 1
    grid [ttk::entry .nb.sweep.ch.p1 -textvariable ::aa::gui::v(ch1_probe) -width 5] -row 1 -column 2
    grid [ttk::label .nb.sweep.ch.r2 -text "CH2 (DUT)"] -row 2 -column 0 -sticky w
    grid [ttk::entry .nb.sweep.ch.s2 -textvariable ::aa::gui::v(ch2_scale) -width 7] -row 2 -column 1
    grid [ttk::entry .nb.sweep.ch.p2 -textvariable ::aa::gui::v(ch2_probe) -width 5] -row 2 -column 2
    grid [ttk::label .nb.sweep.ch.l4 -text "Coupling"] -row 3 -column 0 -sticky w -pady {4 0}
    grid [ttk::combobox .nb.sweep.ch.coup -textvariable ::aa::gui::v(coupling) -values {DC AC} \
              -state readonly -width 5] -row 3 -column 1 -sticky w -pady {4 0}

    ttk::labelframe .nb.sweep.cal -text "Calibration (Short/Open/Load)" -padding 8
    grid [ttk::label .nb.sweep.cal.status -textvariable ::aa::gui::v(cal_status)] -row 0 -column 0 -sticky w
    grid [ttk::button .nb.sweep.cal.go -text "Calibrate..." -command ::aa::gui::do_calibrate] -row 0 -column 1 -padx 8
    grid [ttk::button .nb.sweep.cal.clear -text "Clear" -command ::aa::gui::do_clear_calibration] -row 0 -column 2

    ttk::frame .nb.sweep.run
    set w(runbtn)    [ttk::button .nb.sweep.run.go -text "Run Sweep" -command ::aa::gui::do_run_sweep]
    set w(cancelbtn) [ttk::button .nb.sweep.run.cancel -text Cancel -command ::aa::gui::do_cancel -state disabled]
    set w(progress)  [ttk::progressbar .nb.sweep.run.pb -orient horizontal -length 300 -mode determinate]
    pack $w(runbtn) -side left
    pack $w(cancelbtn) -side left -padx 8
    pack $w(progress) -side left -padx 8

    pack .nb.sweep.range -fill x -pady {0 8}
    pack .nb.sweep.src -fill x -pady {0 8}
    pack .nb.sweep.ch -fill x -pady {0 8}
    pack .nb.sweep.cal -fill x -pady {0 8}
    pack .nb.sweep.run -fill x -pady {0 8}
    update_time_estimate
}

## update_time_estimate -- a rough wall-clock estimate for the configured
## sweep, based on the ~40-45 ms per-SCPI-round-trip floor this app hits in
## practice over plain Tcl sockets (see lib/scpi.tcl's header and
## docs/architecture.rst); each point costs 5 round trips (1 acquire + 2 per
## channel). Purely informational -- it does not gate the Run button.
proc ::aa::gui::update_time_estimate {args} {
    variable v
    if {![string is integer -strict $v(points)] || $v(points) < 2} { set v(time_est) ""; return }
    set per_point 0.25
    set sweep_s [expr {$v(points)*$per_point}]
    set cal_s   [expr {3*$sweep_s}]
    set v(time_est) [format "Estimated: ~%.0f s to sweep, ~%.0f s more to calibrate (3 standards)." $sweep_s $cal_s]
}

# --- Smith chart tab ---------------------------------------------------------
proc ::aa::gui::build_smith_tab {} {
    variable w
    ttk::frame .nb.smith -padding 6
    set w(smith_canvas) [canvas .nb.smith.cv -background white -highlightthickness 0]
    ttk::label .nb.smith.readout -textvariable ::aa::gui::v(readout) -font {Courier 10}
    pack .nb.smith.readout -side bottom -fill x -pady {4 0}
    pack $w(smith_canvas) -fill both -expand 1
    bind $w(smith_canvas) <Configure> ::aa::gui::redraw_smith
    bind $w(smith_canvas) <Motion> {::aa::gui::on_smith_motion %x %y}
}

proc ::aa::gui::redraw_smith {args} {
    variable w
    ::aa::gui::smith::draw_grid $w(smith_canvas)
    ::aa::gui::smith::plot_trace $w(smith_canvas) $::aa::gui::current_dataset -color #1a66cc
}

proc ::aa::gui::on_smith_motion {x y} {
    variable w
    set ds $::aa::gui::current_dataset
    set freqs [dict get $ds freqs]
    if {![llength $freqs]} return
    set gammas [dict get $ds gamma]
    set best -1; set bestd 1e30; set i 0
    foreach g $gammas {
        lassign [::aa::gui::smith::to_xy $w(smith_canvas) $g] px py
        set d [expr {($px-$x)*($px-$x)+($py-$y)*($py-$y)}]
        if {$d < $bestd} { set bestd $d; set best $i }
        incr i
    }
    if {$best < 0} return
    set f [lindex $freqs $best]
    set g [lindex $gammas $best]
    show_point_readout $f $g
    ::aa::gui::smith::mark_point $w(smith_canvas) $g [format "%.3f MHz" [expr {$f/1e6}]]
}

proc ::aa::gui::show_point_readout {f g} {
    variable v
    lassign [aa::calib::z_of_gamma $g $v(z0)] R X
    set swr [aa::calib::swr_of_gamma $g]
    set rl  [aa::calib::rl_of_gamma $g]
    set v(readout) [format "%8.4f MHz   Z = %7.2f %s j%.2f ohm   |Gamma| = %5.3f   SWR = %6.2f   RL = %5.1f dB" \
                        [expr {$f/1e6}] $R [expr {$X>=0?"+":"-"}] [expr {abs($X)}] [aa::complex::cabs $g] $swr $rl]
}

# --- SWR/RL chart tab ---------------------------------------------------------
proc ::aa::gui::build_chart_tab {} {
    variable w
    ttk::frame .nb.chart -padding 6
    ttk::label .nb.chart.l1 -text "SWR vs Frequency" -font {Helvetica 9 bold}
    set w(swr_canvas) [canvas .nb.chart.swr -background white -highlightthickness 0 -height 240]
    ttk::label .nb.chart.l2 -text "Return Loss vs Frequency" -font {Helvetica 9 bold}
    set w(rl_canvas)  [canvas .nb.chart.rl  -background white -highlightthickness 0 -height 200]
    ttk::label .nb.chart.readout -textvariable ::aa::gui::v(readout) -font {Courier 10}
    pack .nb.chart.l1 -anchor w
    pack $w(swr_canvas) -fill both -expand 1
    pack .nb.chart.l2 -anchor w -pady {8 0}
    pack $w(rl_canvas) -fill both -expand 1
    pack .nb.chart.readout -side bottom -fill x -pady {4 0}
    bind $w(swr_canvas) <Configure> ::aa::gui::redraw_charts
    bind $w(rl_canvas)  <Configure> ::aa::gui::redraw_charts
    bind $w(swr_canvas) <Motion> {::aa::gui::on_chart_motion %x}
    bind $w(rl_canvas)  <Motion> {::aa::gui::on_chart_motion %x}
}

proc ::aa::gui::_dataset_curves {ds} {
    set freqs [dict get $ds freqs]
    set swrs {}; set rls {}
    foreach g [dict get $ds gamma] {
        lappend swrs [aa::calib::swr_of_gamma $g]
        lappend rls  [aa::calib::rl_of_gamma $g]
    }
    list $freqs $swrs $rls
}

proc ::aa::gui::redraw_charts {args} {
    variable w
    lassign [_dataset_curves $::aa::gui::current_dataset] freqs swrs rls
    ::aa::gui::plot::draw $w(swr_canvas) $freqs $swrs -ylabel SWR -xlabel "Frequency (MHz)" -logy 1 -refy 2.0
    ::aa::gui::plot::draw $w(rl_canvas)  $freqs $rls  -ylabel "RL (dB)" -xlabel "Frequency (MHz)"
}

proc ::aa::gui::on_chart_motion {x} {
    variable w
    set freqs [dict get $::aa::gui::current_dataset freqs]
    if {![llength $freqs]} return
    set gammas [dict get $::aa::gui::current_dataset gamma]
    # nearest point by pixel x-position (both canvases share the same x mapping)
    set best -1; set bestd 1e30; set i 0
    foreach f $freqs {
        set px [::aa::gui::plot::_sx $w(swr_canvas) $f [lindex $freqs 0] [lindex $freqs end]]
        set d [expr {abs($px-$x)}]
        if {$d < $bestd} { set bestd $d; set best $i }
        incr i
    }
    if {$best < 0} return
    set f [lindex $freqs $best]
    show_point_readout $f [lindex $gammas $best]
    lassign [_dataset_curves $::aa::gui::current_dataset] xs swrs rls
    ::aa::gui::plot::draw $w(swr_canvas) $xs $swrs -ylabel SWR -xlabel "Frequency (MHz)" -logy 1 -refy 2.0 \
        -cursor_x $f -cursor_label [format "%.3f MHz" [expr {$f/1e6}]]
    ::aa::gui::plot::draw $w(rl_canvas) $xs $rls -ylabel "RL (dB)" -xlabel "Frequency (MHz)" \
        -cursor_x $f -cursor_label [format "%.3f MHz" [expr {$f/1e6}]]
}

# --- Data tab ---------------------------------------------------------------
proc ::aa::gui::build_data_tab {} {
    variable w
    ttk::frame .nb.data -padding 6
    set cols {freq R X Z swr rl gamma angle}
    set w(table) [ttk::treeview .nb.data.tv -columns $cols -show headings -height 18]
    foreach {c t wd} {freq "Freq (MHz)" 90 R "R (ohm)" 80 X "X (ohm)" 80 Z "|Z| (ohm)" 80 \
                          swr SWR 70 rl "RL (dB)" 70 gamma "|Gamma|" 70 angle "Angle (deg)" 90} {
        $w(table) heading $c -text $t
        $w(table) column $c -width $wd -anchor e
    }
    ttk::scrollbar .nb.data.sb -orient vertical -command [list $w(table) yview]
    $w(table) configure -yscrollcommand [list .nb.data.sb set]
    ttk::frame .nb.data.btns
    ttk::button .nb.data.btns.csv -text "Export CSV..." -command ::aa::gui::do_export_csv
    ttk::button .nb.data.btns.s1p -text "Export Touchstone (.s1p)..." -command ::aa::gui::do_export_s1p
    pack .nb.data.btns.csv -side left
    pack .nb.data.btns.s1p -side left -padx 8
    pack .nb.data.btns -side bottom -fill x -pady {6 0}
    pack .nb.data.sb -side right -fill y
    pack $w(table) -side left -fill both -expand 1
}

proc ::aa::gui::clear_data_table {} {
    variable w
    $w(table) delete [$w(table) children {}]
}
proc ::aa::gui::append_data_row {f g} {
    variable w; variable v
    lassign [aa::calib::z_of_gamma $g $v(z0)] R X
    set swr [aa::calib::swr_of_gamma $g]
    set rl  [aa::calib::rl_of_gamma $g]
    lassign [aa::complex::c2polar $g] mag rad
    $w(table) insert {} end -values [list \
        [format %.4f [expr {$f/1e6}]] [format %.2f $R] [format %.2f $X] [format %.2f [expr {hypot($R,$X)}]] \
        [format %.3f $swr] [format %.2f $rl] [format %.4f $mag] [format %.1f [expr {$rad*180.0/acos(-1)}]]]
}

# --- SCPI console tab -----------------------------------------------------
proc ::aa::gui::build_console_tab {} {
    variable w
    ttk::frame .nb.console -padding 6
    set w(console_log) [text .nb.console.log -height 20 -wrap none -state disabled \
                             -font {Courier 9} -background #0f1115 -foreground #d8dee9]
    $w(console_log) tag configure TX -foreground #7fb4ff
    $w(console_log) tag configure RX -foreground #8be08b
    $w(console_log) tag configure ERR -foreground #ff8080
    $w(console_log) tag configure INFO -foreground #9aa5b1
    ttk::scrollbar .nb.console.sb -orient vertical -command [list $w(console_log) yview]
    $w(console_log) configure -yscrollcommand [list .nb.console.sb set]

    ttk::frame .nb.console.entryrow
    set w(cmdentry) [ttk::entry .nb.console.entryrow.e -textvariable ::aa::gui::v(cmdline)]
    ttk::button .nb.console.entryrow.send -text Send -command ::aa::gui::do_console_send
    bind $w(cmdentry) <Return> ::aa::gui::do_console_send
    pack .nb.console.entryrow.send -side right
    pack $w(cmdentry) -side left -fill x -expand 1

    pack .nb.console.entryrow -side bottom -fill x -pady {6 0}
    pack .nb.console.sb -side right -fill y
    pack $w(console_log) -side left -fill both -expand 1
}

proc ::aa::gui::console_log {dir text} {
    variable w
    if {![info exists w(console_log)]} return
    $w(console_log) configure -state normal
    $w(console_log) insert end "[format %-4s $dir] $text\n" $dir
    set nlines [lindex [split [$w(console_log) index end] .] 0]
    if {$nlines > 800} { $w(console_log) delete 1.0 "[expr {$nlines-800}].0" }
    $w(console_log) see end
    $w(console_log) configure -state disabled
}

proc ::aa::gui::do_console_send {} {
    variable v
    set cmd [string trim $v(cmdline)]
    if {$cmd eq ""} return
    if {![aa::scpi::connected]} { console_log ERR "not connected"; return }
    if {[string match {*\?*} $cmd]} {
        catch { aa::scpi::query $cmd }
    } else {
        catch { aa::scpi::write $cmd }
    }
    set v(cmdline) ""
}

# ----------------------------------------------------------------- statusbar
proc ::aa::gui::build_statusbar {} {
    ttk::frame .status -padding {8 3}
    ttk::label .status.l -textvariable ::aa::gui::v(status) -anchor w
    pack .status.l -fill x
}

# ------------------------------------------------------------- calibration
proc ::aa::gui::do_clear_calibration {} {
    aa::sweep::clear_calibration
    set ::aa::gui::v(cal_status) "Not calibrated"
    set ::aa::gui::v(status) "Calibration cleared."
}

proc ::aa::gui::_apply_instrument_settings {} {
    variable v
    aa::sweep::configure rs $v(rs) z0 $v(z0) amplitude $v(amplitude) cycles $v(cycles) \
        ch1_scale $v(ch1_scale) ch2_scale $v(ch2_scale) ch1_probe $v(ch1_probe) ch2_probe $v(ch2_probe) \
        coupling $v(coupling)
    aa::driver::configure_source $v(amplitude) 1
    aa::driver::configure_channel 1 $v(ch1_scale) $v(ch1_probe) $v(coupling)
    aa::driver::configure_channel 2 $v(ch2_scale) $v(ch2_probe) $v(coupling)
    aa::scpi::check_errors
}

proc ::aa::gui::_sweep_freqs {} {
    variable v
    set start [expr {$v(start_mhz)*1e6}]
    set stop  [expr {$v(stop_mhz)*1e6}]
    set npts  $v(points)
    if {![string is double -strict $v(start_mhz)] || ![string is double -strict $v(stop_mhz)] \
            || ![string is integer -strict $npts] || $npts < 2 || $stop <= $start || $start <= 0} {
        error "check the sweep range and point count"
    }
    aa::sweep::linspace $start $stop $npts
}

proc ::aa::gui::do_calibrate {} {
    variable w; variable v
    if {![aa::scpi::connected]} { tk_messageBox -icon error -message "Not connected to an instrument."; return }
    if {[catch { set freqs [_sweep_freqs] } err]} { tk_messageBox -icon error -message $err; return }
    if {[catch { _apply_instrument_settings } err]} {
        tk_messageBox -icon error -message "Instrument setup failed:\n$err"; return
    }
    aa::sweep::reset_cancel
    $w(runbtn) configure -state disabled
    .nb.sweep.cal.go configure -state disabled
    array set d {}
    foreach {std prompt} {
        SHORT "Connect a SHORT standard to the test port."
        OPEN  "Connect an OPEN standard (or leave the port unterminated) to the test port."
        LOAD  "Connect a 50 ohm LOAD standard to the test port."
    } {
        set ans [tk_messageBox -icon question -type okcancel -title "Calibration -- $std" \
                     -message "$prompt\n\nClick OK when ready, or Cancel to abort calibration."]
        if {$ans ne "ok"} {
            set v(status) "Calibration cancelled."
            $w(runbtn) configure -state normal; .nb.sweep.cal.go configure -state normal
            return
        }
        set v(status) "Calibrating: $std standard..."
        $w(progress) configure -maximum [llength $freqs] -value 0
        if {[catch {
            set d($std) [aa::sweep::measure_standard $freqs [list ::aa::gui::on_cal_point $std]]
        } err]} {
            tk_messageBox -icon error -message "Calibration failed during $std:\n$err"
            $w(runbtn) configure -state normal; .nb.sweep.cal.go configure -state normal
            return
        }
    }
    aa::sweep::calibrate_build $freqs $d(SHORT) $d(OPEN) $d(LOAD)
    set v(cal_status) "Calibrated: [llength $freqs] points at [clock format [clock seconds] -format {%H:%M:%S}]"
    set v(status) "Calibration complete."
    $w(runbtn) configure -state normal; .nb.sweep.cal.go configure -state normal
}

proc ::aa::gui::on_cal_point {std i n f} {
    variable w; variable v
    $w(progress) configure -value $i
    set v(status) [format "Calibrating %s: %.4f MHz (%d/%d)" $std [expr {$f/1e6}] $i $n]
    update idletasks
}

# ----------------------------------------------------------------- sweep run
proc ::aa::gui::do_run_sweep {} {
    variable w; variable v
    if {![aa::scpi::connected]} { tk_messageBox -icon error -message "Not connected to an instrument."; return }
    if {[catch { set freqs [_sweep_freqs] } err]} { tk_messageBox -icon error -message $err; return }
    if {[catch { _apply_instrument_settings } err]} {
        tk_messageBox -icon error -message "Instrument setup failed:\n$err"; return
    }
    set ::aa::gui::live_freqs {}
    set ::aa::gui::live_gammas {}
    clear_data_table
    set ::aa::gui::current_dataset [dict create freqs {} gamma {}]
    redraw_all $::aa::gui::current_dataset

    $w(runbtn) configure -state disabled
    $w(cancelbtn) configure -state normal
    $w(progress) configure -maximum [llength $freqs] -value 0
    set v(status) [expr {[aa::sweep::have_calibration] ? "Sweeping..." : "Sweeping (uncalibrated)..."}]
    update idletasks

    set result {}
    if {[catch { set result [aa::sweep::run $freqs ::aa::gui::on_sweep_point] } err]} {
        set v(status) "Sweep error: $err"
        $w(runbtn) configure -state normal
        $w(cancelbtn) configure -state disabled
        return
    }
    $w(runbtn) configure -state normal
    $w(cancelbtn) configure -state disabled
    set ds [dict get $result dataset]
    set ::aa::gui::current_dataset $ds
    redraw_all $ds
    set n [llength [dict get $ds freqs]]
    if {[dict get $result ok]} {
        set v(status) [format_completion_status $ds]
    } else {
        set v(status) "Sweep cancelled ($n of [llength $freqs] points kept)."
    }
}

proc ::aa::gui::format_completion_status {ds} {
    set freqs [dict get $ds freqs]
    if {![llength $freqs]} { return "Sweep complete (no points)." }
    set gammas [dict get $ds gamma]
    set bestf [lindex $freqs 0]; set bestswr [aa::calib::swr_of_gamma [lindex $gammas 0]]
    foreach f $freqs g $gammas {
        set s [aa::calib::swr_of_gamma $g]
        if {$s < $bestswr} { set bestswr $s; set bestf $f }
    }
    format "Sweep complete. Minimum SWR %.2f at %.4f MHz." $bestswr [expr {$bestf/1e6}]
}

proc ::aa::gui::do_cancel {} { aa::sweep::cancel }

proc ::aa::gui::on_sweep_point {i n f gamma} {
    variable w; variable v
    lappend ::aa::gui::live_freqs $f
    lappend ::aa::gui::live_gammas $gamma
    $w(progress) configure -value $i
    set v(status) [format "Sweeping: %.4f MHz (%d/%d)" [expr {$f/1e6}] $i $n]
    set ds [dict create freqs $::aa::gui::live_freqs gamma $::aa::gui::live_gammas]
    set ::aa::gui::current_dataset $ds
    redraw_all $ds
    append_data_row $f $gamma
    update idletasks
}

proc ::aa::gui::redraw_all {ds} {
    set ::aa::gui::current_dataset $ds
    redraw_smith
    redraw_charts
}

# ----------------------------------------------------------------- export
proc ::aa::gui::do_export_csv {} {
    if {![llength [dict get $::aa::gui::current_dataset freqs]]} {
        tk_messageBox -icon error -message "No sweep data yet."; return
    }
    set path [tk_getSaveFile -defaultextension .csv -filetypes {{CSV .csv}} -initialfile sweep.csv]
    if {$path eq ""} return
    aa::calib::write_csv $path $::aa::gui::current_dataset $::aa::gui::v(z0)
    set ::aa::gui::v(status) "Wrote $path"
}
proc ::aa::gui::do_export_s1p {} {
    if {![llength [dict get $::aa::gui::current_dataset freqs]]} {
        tk_messageBox -icon error -message "No sweep data yet."; return
    }
    set path [tk_getSaveFile -defaultextension .s1p -filetypes {{Touchstone .s1p}} -initialfile sweep.s1p]
    if {$path eq ""} return
    aa::calib::write_s1p $path $::aa::gui::current_dataset $::aa::gui::v(z0)
    set ::aa::gui::v(status) "Wrote $path"
}
