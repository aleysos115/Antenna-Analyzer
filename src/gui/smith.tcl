#
# smith.tcl -- draws a Smith chart on a Tk canvas and plots a swept Gamma
# trace on top of it.
#
# The mapping from a normalized reflection coefficient Gamma={re im} to
# canvas pixels is a similarity transform (uniform scale, a y-flip because
# canvas y grows downward, plus a translation to the canvas center) --
# it turns circles into circles, which is what makes the constant-R and
# constant-X Smith chart gridlines drawable at all: every one of them is a
# circle (or, for X=0, a straight line) in the Gamma-plane, so it is still a
# circle (or line) once mapped to pixels.
#
# Depends on: complex.tcl (for cabs, used to trim reactance arcs to the part
# that lies inside the unit circle)
#
namespace eval ::aa::gui::smith {
    variable geom          ;# array: cx cy r (canvas pixel center + unit-circle radius), per canvas
    variable r_values {0.2 0.5 1 2 5}
    variable x_values {0.2 0.5 1 2 5}
}

## compute_geom cv -- (re)compute the canvas-pixel center/radius for canvas
## $cv from its current size, leaving a margin for labels. Call this from a
## <Configure> binding as well as before the first draw.
proc ::aa::gui::smith::compute_geom {cv} {
    variable geom
    set w [winfo width $cv]
    set h [winfo height $cv]
    if {$w < 20} { set w 400 }
    if {$h < 20} { set h 400 }
    set margin 26
    set r [expr {(min($w,$h) - 2*$margin) / 2.0}]
    if {$r < 10} { set r 10 }
    set geom($cv,cx) [expr {$w/2.0}]
    set geom($cv,cy) [expr {$h/2.0}]
    set geom($cv,r)  $r
}

## to_xy cv gamma -- map a Gamma={re im} point to {x y} canvas pixels
proc ::aa::gui::smith::to_xy {cv gamma} {
    variable geom
    lassign $gamma re im
    list [expr {$geom($cv,cx) + $re*$geom($cv,r)}] \
         [expr {$geom($cv,cy) - $im*$geom($cv,r)}]
}

## px cv length -- scale a Gamma-plane length (e.g. a circle radius) to pixels
proc ::aa::gui::smith::px {cv length} { variable geom; expr {$length*$geom($cv,r)} }

# --- one reactance arc, x=const, sampled and trimmed to inside the unit circle ---
proc ::aa::gui::smith::_reactance_points {x n} {
    set cxg 1.0
    set cyg [expr {1.0/$x}]
    set rad [expr {1.0/abs($x)}]
    set pts {}
    for {set i 0} {$i <= $n} {incr i} {
        set th [expr {2*acos(-1)*$i/double($n)}]
        set gx [expr {$cxg + $rad*cos($th)}]
        set gy [expr {$cyg + $rad*sin($th)}]
        if {$gx*$gx + $gy*$gy <= 1.0 + 1e-6} { lappend pts [list $gx $gy] }
    }
    # `pts` may wrap across the i=0/n seam (a single contiguous arc split into
    # a head run and a tail run); if so, splice the tail in front of the head.
    if {[llength $pts] == 0} { return {} }
    return $pts
}

## draw_grid cv -- clear the canvas and draw the Smith chart gridlines. Call
## after compute_geom (or draw does that for you if you call it directly).
proc ::aa::gui::smith::draw_grid {cv {bg #ffffff} {gridcolor #b9c2cc} {boldcolor #55606b}} {
    variable geom; variable r_values; variable x_values
    compute_geom $cv
    $cv delete all
    $cv configure -background $bg
    set cx $geom($cv,cx); set cy $geom($cv,cy); set r $geom($cv,r)

    # outer boundary |Gamma|=1 and the resistance axis (X=0 diameter)
    $cv create oval [expr {$cx-$r}] [expr {$cy-$r}] [expr {$cx+$r}] [expr {$cy+$r}] \
        -outline $boldcolor -width 1.6 -tags gridline
    $cv create line [expr {$cx-$r}] $cy [expr {$cx+$r}] $cy -fill $gridcolor -tags gridline

    # constant-resistance circles (fully inside the unit disk, so a plain oval)
    foreach rv $r_values {
        set cxg [expr {$rv/(1.0+$rv)}]
        set rad [expr {1.0/(1.0+$rv)}]
        lassign [to_xy $cv [list $cxg 0]] px py
        set pr [px $cv $rad]
        set w [expr {$rv == 1 ? 1.4 : 0.8}]
        $cv create oval [expr {$px-$pr}] [expr {$py-$pr}] [expr {$px+$pr}] [expr {$py+$pr}] \
            -outline $gridcolor -width $w -tags gridline
        lassign [to_xy $cv [list [expr {2*$cxg-1.0}] 0]] lx ly
        $cv create text [expr {$lx+3}] [expr {$ly-2}] -text $rv -anchor sw \
            -fill $boldcolor -font {Helvetica 7} -tags gridline
    }

    # constant-reactance arcs, +x above the axis, -x (mirrored) below
    foreach xv $x_values {
        foreach sign {1 -1} {
            set xx [expr {$sign*$xv}]
            set gpts [_reactance_points $xx 240]
            if {[llength $gpts] < 2} continue
            set flat {}
            foreach p $gpts { lassign [to_xy $cv $p] px py; lappend flat $px $py }
            set w [expr {$xv == 1 ? 1.2 : 0.7}]
            $cv create line {*}$flat -fill $gridcolor -width $w -smooth 1 -tags gridline
        }
    }
    $cv create text $cx [expr {$cy+$r+13}] -text {Z0-normalized Smith chart} \
        -fill $boldcolor -font {Helvetica 8} -tags gridline
}

## plot_trace cv dataset ?options...? -- draw a swept Gamma trace on top of
## a chart already drawn with draw_grid. dataset is an aa::calib dataset
## (dict with "freqs" and "gamma" keys). Options: -color, -width, -dots (0/1),
## -tag (canvas tag to use, so a later redraw can `$cv delete $tag` this trace
## specifically without touching the grid).
proc ::aa::gui::smith::plot_trace {cv dataset args} {
    array set opt {-color #1a66cc -width 2 -dots 1 -tag trace}
    array set opt $args
    $cv delete $opt(-tag)
    set freqs [dict get $dataset freqs]
    set gammas [dict get $dataset gamma]
    if {[llength $freqs] == 0} return
    set flat {}
    foreach g $gammas { lassign [to_xy $cv $g] px py; lappend flat $px $py }
    if {[llength $flat] >= 4} {
        $cv create line {*}$flat -fill $opt(-color) -width $opt(-width) -tags $opt(-tag)
    }
    if {$opt(-dots)} {
        foreach g $gammas {
            lassign [to_xy $cv $g] px py
            $cv create oval [expr {$px-1.6}] [expr {$py-1.6}] [expr {$px+1.6}] [expr {$py+1.6}] \
                -fill $opt(-color) -outline {} -tags $opt(-tag)
        }
    }
}

## mark_point cv gamma label ?color? ?tag? -- a highlighted marker (e.g. the
## frequency the cursor is nearest to, or the minimum-SWR point).
proc ::aa::gui::smith::mark_point {cv gamma label {color #e0451c} {tag marker}} {
    $cv delete $tag
    lassign [to_xy $cv $gamma] px py
    $cv create oval [expr {$px-4}] [expr {$py-4}] [expr {$px+4}] [expr {$py+4}] \
        -fill $color -outline #ffffff -width 1 -tags $tag
    $cv create text [expr {$px+7}] [expr {$py-7}] -text $label -anchor sw \
        -fill $color -font {Helvetica 8 bold} -tags $tag
}
