Antenna Analyzer
================

Read the docs at:

https://antenna-analyzer.readthedocs.io/en/latest/

Tcl/Tk Antenna Analyzer
-----------------------

A two-channel-oscilloscope-plus-signal-generator vector reflection
analyzer: it turns a DSO2000-family scope with a built-in arbitrary
waveform generator into an instrument that sweeps frequency, measures
complex reflection coefficient (Γ), and reports impedance, SWR, and return
loss for an antenna or any one-port device — entirely over SCPI, with a
Tcl/Tk GUI on top.

.. code-block:: shell

    pip install sphinx sphinx-rtd-theme
    sphinx-build -b html docs docs/_build/html


Quickstart
----------

No hardware needed to try it — a simulated instrument is included:

.. code-block:: shell

    tclsh src/mock/mockscope.tcl 5025
    wish src/bin/antenna_analyzer.tcl


Connect to `127.0.0.1:5025`, calibrate, sweep. See 'docs/quickstart.rst <docs/quickstart.rst>'_ for the full walkthrough with
screenshots.

Layout
------
All the code is contained within the **src** folder.

.. code-block:: text

    bin/antenna_analyzer.tcl     entry point: wish bin/antenna_analyzer.tcl
    lib/                         instrument-free of Tk; usable from plain tclsh
      complex.tcl                complex-number arithmetic
      dsp.tcl                    single-bin DFT phasor extraction (software lock-in)
      calib.tcl                  SOL calibration, Gamma -> Z/SWR/RL, Touchstone/CSV export
      scpi.tcl                   transport-agnostic SCPI client (TCP + USBTMC)
      driver.tcl                 semantic instrument operations + mnemonic profile
      sweep.tcl                  measurement/calibration/sweep orchestration
    gui/
      app.tcl                    the application
      smith.tcl                  Smith chart canvas drawing
      plot.tcl                   XY line-plot canvas drawing
    mock/mockscope.tcl           simulated scope+generator for development without hardware
    tests/
      unit.test                  tcltest suite for lib/complex, dsp, calib
      mock_selftest.tcl          end-to-end test against mock/mockscope.tcl
    docs/                        Sphinx documentation source (+ built HTML in docs/_build/html)


Running the tests
-----------------
unit.test : pure-math unit tests, no instrument needed

mock_selftest.tcl : end-to-end test against the mock instrument

.. code-block:: shell

    tclsh src/tests/unit.test              
    tclsh src/tests/mock_selftest.tcl  

Status
------

A hobbyist/educational project, not a commercial product or a substitute
for a real VNA. See `docs/performance.rst <docs/performance.rst>`_ for expected sweep timing and
`docs/calibration_theory.rst <docs/calibration_theory.rst>`_ for the accuracy model. The default SCPI
mnemonics match the included mock instrument but have not been verified
against a specific real DSO2000 unit's programmer's manual — see
`docs/scpi_reference.rst <docs/scpi_reference.rst>`_ for adapting them.

License
-------

MIT — see `LICENSE <./LICENSE>`_.
