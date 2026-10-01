#!/usr/bin/env python3
"""Generate docs/images/schematic_testhead.svg -- the analog test-head
circuit: signal generator, series resistor, DUT, and where CH1/CH2 tap in.
Run from anywhere; writes next to this script's docs/images/ directory.
"""
import os
import schemdraw
import schemdraw.elements as elm

here = os.path.dirname(os.path.abspath(__file__))
outdir = os.path.join(here, "images")
os.makedirs(outdir, exist_ok=True)

schemdraw.theme("default")

with schemdraw.Drawing(file=os.path.join(outdir, "schematic_testhead.svg")) as d:
    d.config(fontsize=12, unit=2.5)

    src = d.add(elm.SourceSin().up().label("AWG", loc="left"))
    d.add(elm.Line().right().at(src.end))
    n1 = d.add(elm.Dot())

    ch1 = d.add(elm.Line().up().length(1.6).at(n1.start))
    d.add(elm.Arrowhead().at(ch1.end).theta(90))
    d.add(elm.Label().at((ch1.end[0] + 0.18, ch1.end[1] - 0.15)).label("CH1\n(source)", loc="right"))

    rs = d.add(elm.Resistor().right().at(n1.start).label("Rs\n50 $\\Omega$", loc="bottom"))
    n2 = d.add(elm.Dot())

    ch2 = d.add(elm.Line().up().length(1.6).at(n2.start))
    d.add(elm.Arrowhead().at(ch2.end).theta(90))
    d.add(elm.Label().at((ch2.end[0] + 0.18, ch2.end[1] - 0.15)).label("CH2\n(DUT)", loc="right"))

    ant = d.add(elm.Antenna().right().at(n2.start).label("DUT\n(antenna under test,\nor a Short/Open/Load\ncal standard)", loc="right"))

    d.add(elm.Ground().at(src.start))
    d.add(elm.Label().at((src.start[0] - 0.3, src.start[1] - 0.9)).label("AWG return /\nchassis ground", loc="left"))

d_bottom = None
print("wrote", os.path.join(outdir, "schematic_testhead.svg"))
