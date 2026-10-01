Testing
========

Two independent test paths cover this project: pure-math unit tests that
need no instrument at all, and an end-to-end test against a simulated one.

Unit tests
-----------

.. code-block:: console

   $ tclsh tests/unit.test
   unit.test:	Total	22	Passed	22	Skipped	0	Failed	0

``tests/unit.test`` uses the standard ``tcltest`` package against
``complex.tcl``, ``dsp.tcl``, and ``calib.tcl`` -- the three modules with no
Tk or instrument dependency. A few of these are worth knowing about
because they pin down real bugs found while building this app, not just
generic sanity checks:

* **complex-1.1** asserts that :tcl:`::aa::complex::cadd {1 2} {3 -1}`
  returns ``{4.0 1.0}``, not ``{4 1}``. This looks pedantic until you know
  why it matters: see the next point.
* **calib-3.2** specifically re-measures a calibration standard against
  itself (:math:`M = M_s`) and asserts the result is finite and exactly
  :math:`\Gamma = -1`. The *first* version of :tcl:`::aa::calib::sol_correct`
  used the textbook cross-ratio formula, which divides by exactly zero at
  that input -- caught by this test, not a human running a sweep and
  silently assuming a crashed calibration confirmation step was pre-existing
  brokenness. See :doc:`calibration_theory` for the fix.
* **calib-3.4** checks that an ideal open (:math:`\Gamma=1`) returns an
  explicit ``{Inf 0}`` impedance rather than raising, since that's the
  physically correct answer, not an error condition.

Run just the pure-math tests before touching ``complex.tcl``, ``dsp.tcl``,
or ``calib.tcl`` -- they take under a second and need no mock server.

The mock instrument
-----------------------

``mock/mockscope.tcl`` is a from-scratch SCPI server (plain ``socket
-server``, no external packages) that answers the same mnemonic set the
default :doc:`driver profile <scpi_reference>` expects. It isn't a
recording or a stub -- it has an actual signal model behind it:

.. code-block:: text

   AWG --+--[Rs]--+-- DUT          H = V2/V1 = 1 / (1 + Rs * Y_dut)
         CH1      CH2

``:SINGle`` synthesizes both channels' waveforms from that model, including
deliberate, realistic imperfections: a few percent of CH2 gain error, a
couple of nanoseconds of CH1/CH2 skew, stray capacitance at the DUT node,
8-bit ADC quantization with clipping, and additive noise. The DUT itself
switches between a short, an open, a resistive load, and a ~7.1 MHz
series-RLC "antenna" via a back door no real instrument has:

.. code-block:: tcl

   :SIMulate:DUT SHORT|OPEN|LOAD|ANT   ;# choose what's "connected"
   :SIMulate:GAMMa?                     ;# ask for the true Gamma (ground truth)

That ground-truth query is what makes the end-to-end test meaningful: it's
not just checking that the app doesn't crash, it's checking that a full
calibrate-then-sweep run recovers the *actual* answer to within a
numerical tolerance, through real SCPI traffic over a real (loopback) TCP
socket, exercising the exact same code path a real instrument session
would.

Start it standalone for interactive use (e.g. to try the GUI, see
:doc:`quickstart`):

.. code-block:: console

   $ tclsh mock/mockscope.tcl 5025
   mockscope listening on 127.0.0.1:5025

End-to-end test
-------------------

.. code-block:: console

   $ tclsh tests/mock_selftest.tcl
   ...
   max |Gamma error| vs ground truth: 0.0053
   PASS

This script starts the mock itself, connects through the real
``lib/scpi.tcl`` transport, drives a full Short/Open/Load calibration and a
24-point sweep of the simulated antenna through ``lib/sweep.tcl``, and
compares every corrected :math:`\Gamma` against ``:SIMulate:GAMMa?``'s
ground truth -- typically agreeing to within :math:`|\Gamma|<0.01` despite
the mock's deliberately-injected channel imperfections. It also exercises
error-queue handling (deliberately sends an out-of-range value and an
undefined command, then asserts :tcl:`::aa::scpi::check_errors` raises)
and the Touchstone/CSV export path.

A note on headless GUI testing
-----------------------------------

The GUI itself (``gui/app.tcl``) was developed and is exercised the same
way: a driver script sources it under ``wish`` with no visible display
(``Xvfb``), calls its button-handler procs directly
(:tcl:`::aa::gui::do_connect`, :tcl:`::aa::gui::do_calibrate`,
:tcl:`::aa::gui::do_run_sweep`, ...) in place of real clicks, and -- since
``tk_messageBox`` would otherwise block forever waiting for a human to
click a dialog that doesn't exist in a headless session -- temporarily
redefines ``tk_messageBox`` to answer automatically. Every screenshot in
this documentation was produced that way: the real app, driven
programmatically, with its canvases exported via ``postscript`` or the
whole window grabbed with ImageMagick's ``import -window``, not mockups.

This caught a real bug the unit tests couldn't have: an early
:tcl:`::aa::gui::redraw_all` took a dataset argument and never used it,
silently reading stale global state instead, which only showed up once the
GUI was actually driven through a full connect-calibrate-sweep sequence
and the very first redraw (before any data existed) hit an uninitialized
dict and raised. (A second-order lesson from the same session: the
headless test's ``tk_messageBox`` stub initially didn't switch the mock's
``:SIMulate:DUT`` between Short/Open/Load the way a human physically
swapping a connector would -- producing a "successful" calibration that
was actually calibrated against the same short three times over, and
non-physical output. The bug was in the test harness, not the app, which
is its own small lesson in not trusting a green checkmark without looking
at the actual numbers it produced.)
