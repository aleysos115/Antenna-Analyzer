#
# plot.tcl -- a minimal XY line-plot drawer for a Tk canvas: axes, gridlines,
# tick labels, one data series, an optional threshold reference line, and an
# optional vertical cursor. Deliberately small and hand-rolled (no Plotchart
# dependency) so the styling matches the rest of the app exactly and the
# whole rendering path is inspectable in one file.
#
namespace eval ::aa::gui::plot {
    variable geom     ;# array: left top right bottom (plot-area pixel bounds), per canvas
}

proc ::aa::gui::plot::_sx {cv x xmin xmax} {
    variable geom
    set pw [expr {$geom($cv,right)-$geom($cv,left)}]
    expr {$geom($cv,left) + ($x-$xmin)/double($xmax-$xmin)*$pw}
}
proc ::aa::gui::plot::_sy {cv y ymin ymax logy} {
    variable geom
    if {$logy} { set y [expr {log(max($y,1e-9))}] }
    set ph [expr {$geom($cv,bottom)-$geom($cv,top)}]
    expr {$geom($cv,bottom) - ($y-$ymin)/double($ymax-$ymin)*$ph}
}

## draw cv xs ys args -- redraw canvas $cv as an XY line plot of ys vs xs.
## Required: xs and ys are equal-length lists of numbers (xs ascending).
## Options:
##   -xlabel/-ylabel   axis captions
##   -ymin/-ymax       fixed y-range (default: auto from data, with headroom)
##   -logy 0|1         log-scale y axis (for SWR, which spans orders of magnitude)
##   -color            line color (default steel blue)
##   -refy value       draw a dashed horizontal reference line at this y (e.g. SWR=2)
##   -refcolor         color for -refy
##   -cursor_x value   draw a vertical cursor line at this x (e.g. hovered freq)
##   -cursor_label     text near the cursor
proc ::aa::gui::plot::draw {cv xs ys args} {
    variable geom
    array set opt {
        -xlabel {} -ylabel {} -ymin {} -ymax {} -logy 0 -color #1a66cc
        -refy {} -refcolor #c0392b -cursor_x {} -cursor_label {}
    }
    array set opt $args

    set w [winfo width $cv];  if {$w < 20} { set w 500 }
    set h [winfo height $cv]; if {$h < 20} { set h 260 }
    $cv delete all
    $cv configure -background #ffffff

    set left 46; set right 14; set top 20; set bottom 38
    set geom($cv,left) $left; set geom($cv,top) $top
    set geom($cv,right) [expr {$w-$right}]; set geom($cv,bottom) [expr {$h-$bottom}]
    set pw [expr {$geom($cv,right)-$left}]
    set ph [expr {$geom($cv,bottom)-$top}]

    if {[llength $xs] == 0} {
        $cv create text [expr {$w/2}] [expr {$h/2}] -text {no data yet -- run a sweep} \
            -fill #8a94a0 -font {Helvetica 9}
        return
    }

    set xmin [lindex $xs 0]; set xmax [lindex $xs end]
    if {$xmin == $xmax} { set xmax [expr {$xmin+1}] }

    if {$opt(-ymin) ne "" && $opt(-ymax) ne ""} {
        set ymin $opt(-ymin); set ymax $opt(-ymax)
    } else {
        set ymin [lindex $ys 0]; set ymax $ymin
        foreach v $ys { if {$v<$ymin} {set ymin $v}; if {$v>$ymax} {set ymax $v} }
        if {$opt(-refy) ne ""} {
            if {$opt(-refy)<$ymin} {set ymin $opt(-refy)}
            if {$opt(-refy)>$ymax} {set ymax $opt(-refy)}
        }
        set span [expr {$ymax-$ymin}]
        if {$span <= 0} { set span [expr {abs($ymax)>0 ? abs($ymax)*0.1 : 1.0}] }
        set ymin [expr {$ymin-0.08*$span}]
        set ymax [expr {$ymax+0.12*$span}]
        if {$opt(-ymin) ne ""} { set ymin $opt(-ymin) }
        if {$opt(-ymax) ne ""} { set ymax $opt(-ymax) }
    }
    if {$opt(-logy)} {
        if {$ymin <= 0} { set ymin 0.01 }
        set ymin [expr {log($ymin)}]; set ymax [expr {log($ymax)}]
    }

    # axes box + horizontal gridlines/ticks (5 divisions)
    $cv create rectangle $left $top $geom($cv,right) $geom($cv,bottom) -outline #c7cdd4
    for {set i 0} {$i <= 4} {incr i} {
        set frac [expr {$i/4.0}]
        set yval [expr {$ymin + $frac*($ymax-$ymin)}]
        set ypix [expr {$geom($cv,bottom) - $frac*$ph}]
        $cv create line $left $ypix $geom($cv,right) $ypix -fill #eef1f4
        set label [expr {$opt(-logy) ? [format %.2f [expr {exp($yval)}]] : [format %.2f $yval]}]
        $cv create text [expr {$left-6}] $ypix -text $label -anchor e -font {Helvetica 8} -fill #55606b
    }
    # x ticks (5 divisions), labeled in MHz
    for {set i 0} {$i <= 4} {incr i} {
        set frac [expr {$i/4.0}]
        set xval [expr {$xmin + $frac*($xmax-$xmin)}]
        set xpix [_sx $cv $xval $xmin $xmax]
        $cv create text $xpix [expr {$geom($cv,bottom)+11}] -text [format %.2f [expr {$xval/1e6}]] \
            -anchor n -font {Helvetica 8} -fill #55606b
    }
    if {$opt(-xlabel) ne ""} {
        $cv create text [expr {($left+$geom($cv,right))/2.0}] [expr {$geom($cv,bottom)+24}] -text $opt(-xlabel) \
            -anchor n -font {Helvetica 8} -fill #55606b
    }
    if {$opt(-ylabel) ne ""} {
        $cv create text 4 2 -text $opt(-ylabel) -anchor nw -font {Helvetica 8} -fill #55606b
    }

    if {$opt(-refy) ne ""} {
        set ry [_sy $cv $opt(-refy) $ymin $ymax $opt(-logy)]
        $cv create line $left $ry $geom($cv,right) $ry -fill $opt(-refcolor) -dash {4 3}
    }

    set flat {}
    foreach x $xs y $ys { lappend flat [_sx $cv $x $xmin $xmax] [_sy $cv $y $ymin $ymax $opt(-logy)] }
    if {[llength $flat] >= 4} { $cv create line {*}$flat -fill $opt(-color) -width 1.8 }

    if {$opt(-cursor_x) ne ""} {
        set cxp [_sx $cv $opt(-cursor_x) $xmin $xmax]
        $cv create line $cxp $top $cxp $geom($cv,bottom) -fill #8a94a0 -dash {2 2}
        if {$opt(-cursor_label) ne ""} {
            $cv create text $cxp [expr {$top+2}] -text $opt(-cursor_label) -anchor nw \
                -font {Helvetica 8} -fill #333333
        }
    }
}
