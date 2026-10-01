Changelog
==========

0.1.0
------

Initial build.

* ``lib/``: complex-number arithmetic, single-bin DFT phasor extraction,
  one-port SOL calibration with Touchstone/CSV export, a transport-agnostic
  SCPI client (TCP + USBTMC) built on non-blocking ``vwait``-based I/O, a
  mnemonic-profile driver layer, and sweep/calibration orchestration.
* ``gui/``: a five-tab Tk application -- Sweep settings and calibration
  wizard, Smith chart, SWR/Return Loss charts, a data table, and a live
  SCPI console with a manual command entry.
* ``mock/mockscope.tcl``: a from-scratch simulated scope+generator with a
  real signal model (including deliberately injected channel gain/skew/
  stray-capacitance errors) and a ground-truth back door, used for all
  development and testing without hardware.
* ``tests/``: a ``tcltest`` unit suite for the instrument-free modules, and
  an end-to-end test against the mock instrument comparing calibrated
  output to ground truth.
* This documentation site.

Notable fixes made during initial development (kept here rather than lost
to history, since each one is a small lesson documented in more detail
elsewhere on this site):

* The textbook cross-ratio SOL calibration formula has a removable
  singularity at the short standard's own measured value -- replaced with
  an algebraically equivalent closed form with no such singularity. See
  :doc:`calibration_theory`.
* Tcl's ``/`` operator performs true integer division when both operands
  are integers (``expr {1/3}`` is ``0``), which could have silently
  truncated results anywhere a calculation's intermediates happened to be
  exact integers -- plausible given the calibration standards are
  literally :math:`-1, 0, 1`. Fixed by coercing to ``double`` immediately
  after extracting real/imaginary parts in every ``complex.tcl`` proc, not
  just where a problem happened to be observed. See :doc:`testing`.
* IEEE-488.2 binary block transfers (waveform data) were being corrupted by
  the default ``-translation auto`` channel setting silently collapsing
  coincidental ``\r\n`` byte pairs inside the binary payload. Fixed with
  ``-translation binary`` on both transports. See :doc:`architecture`.
* An early sweep implementation issued several small, individually-
  unacknowledged SCPI writes per measurement point, which stalled on
  Nagle/delayed-ACK interaction; fixed by compounding related commands
  into single writes. See :doc:`performance`.
* A GUI redraw function accepted a dataset argument and silently ignored
  it in favor of stale global state -- caught only once the GUI was driven
  through a full workflow headlessly, not by unit tests. See
  :doc:`testing`.
