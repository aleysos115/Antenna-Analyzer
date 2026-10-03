#
# complex.tcl -- minimal complex-number arithmetic.
#
# A complex number is represented as a plain 2-element Tcl list {re im}.
# There is no object/struct: this keeps every value inspectable with a bare
# `puts` and lets it flow through normal Tcl list commands.
#
package provide aa::complex 1.0

namespace eval ::aa::complex {
    namespace export c cadd csub cmul cdiv cconj cabs carg cexp c2polar polar2c
    namespace ensemble create
}

## c re im -- construct a complex number. c 1 -- is the same as {1 0}.
proc ::aa::complex::c {re {im 0}} { list [expr {double($re)}] [expr {double($im)}] }

## -- Every proc below coerces its real/imaginary parts to double() the
## instant it extracts them, before any arithmetic touches them. This isn't
## just cosmetic (so cadd {1 2} {3 -1} prints {4.0 1.0} rather than {4 1}):
## Tcl's `/` operator does true *integer* division when both operands are
## integers (`expr {1/3}` is 0, not 0.333...). The calibration standards in
## calib.tcl are literally {-1 0}, {1 0}, {0 0} -- exact integers -- so
## without this coercion, cdiv's division could silently truncate whenever
## a calculation involving a standard happened to land on integer
## intermediates. Coercing right after lassign, before any arithmetic, means
## every downstream operation in every proc here is guaranteed to be
## floating-point, with no case-by-case reasoning required.

## cadd a b -- a + b
proc ::aa::complex::cadd {a b} {
    lassign $a ar ai; lassign $b br bi
    set ar [expr {double($ar)}]; set ai [expr {double($ai)}]
    set br [expr {double($br)}]; set bi [expr {double($bi)}]
    list [expr {$ar+$br}] [expr {$ai+$bi}]
}

## csub a b -- a - b
proc ::aa::complex::csub {a b} {
    lassign $a ar ai; lassign $b br bi
    set ar [expr {double($ar)}]; set ai [expr {double($ai)}]
    set br [expr {double($br)}]; set bi [expr {double($bi)}]
    list [expr {$ar-$br}] [expr {$ai-$bi}]
}

## cmul a b -- a * b
proc ::aa::complex::cmul {a b} {
    lassign $a ar ai; lassign $b br bi
    set ar [expr {double($ar)}]; set ai [expr {double($ai)}]
    set br [expr {double($br)}]; set bi [expr {double($bi)}]
    list [expr {$ar*$br-$ai*$bi}] [expr {$ar*$bi+$ai*$br}]
}

## cdiv a b -- a / b
proc ::aa::complex::cdiv {a b} {
    lassign $a ar ai; lassign $b br bi
    set ar [expr {double($ar)}]; set ai [expr {double($ai)}]
    set br [expr {double($br)}]; set bi [expr {double($bi)}]
    set d [expr {$br*$br+$bi*$bi}]
    if {$d == 0} { error "complex division by zero" }
    list [expr {($ar*$br+$ai*$bi)/$d}] [expr {($ai*$br-$ar*$bi)/$d}]
}

## cconj a -- complex conjugate
proc ::aa::complex::cconj {a} {
    lassign $a ar ai
    list [expr {double($ar)}] [expr {double(-$ai)}]
}

## cabs a -- magnitude |a|
proc ::aa::complex::cabs {a} { lassign $a ar ai; expr {hypot($ar,$ai)} }

## carg a -- phase of a, radians, in (-pi, pi]
proc ::aa::complex::carg {a} { lassign $a ar ai; expr {atan2($ai,$ar)} }

## cexp theta -- unit phasor e^(i*theta)
proc ::aa::complex::cexp {theta} { list [expr {cos($theta)}] [expr {sin($theta)}] }

## c2polar a -- {magnitude radians}
proc ::aa::complex::c2polar {a} { list [cabs $a] [carg $a] }

## polar2c mag theta -- construct from magnitude + radians
proc ::aa::complex::polar2c {mag theta} { list [expr {$mag*cos($theta)}] [expr {$mag*sin($theta)}] }
