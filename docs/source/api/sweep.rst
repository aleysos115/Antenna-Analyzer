``sweep.tcl``
=============

Measurement / calibration / sweep orchestration. Namespace: ``::aa::sweep``. Source: ``lib/sweep.tcl``.

.. py:function:: configure args
   :noindex:

   update one or more settings, e.g.

   ::aa::sweep::configure rs 51.3 amplitude 0.5

.. py:function:: linspace lo hi n
   :noindex:

   n frequencies from lo to hi Hz inclusive, ascending.

.. py:function:: measure_h f
   :noindex:

   one calibration-free measurement at frequency f (Hz).

   Configures the source/timebase, triggers a single acquisition, downloads both channels, and returns the complex ratio H = V2/V1 via a matched single-bin DFT (dsp::phasor) on each channel.

.. py:function:: measure_standard freqs ?statuscb?
   :noindex:

   sweep measure_h across freqs and return

   a dict {freq -> H}. statuscb, if non-empty, is called as "{\*}$statuscb $doneCount $total $f" after every point (progress reporting; it may safely touch the GUI, since this loop runs on the main thread and between-point code -- not inside a query -- is where we're called back). Honors ::aa::sweep::cancel: returns whatever was collected so far.

.. py:function:: calibrate_build freqs shortD openD loadD
   :noindex:

   combine three per-frequency

   measure_standard results (for SHORT/OPEN/LOAD) into the calibration dict used by `run`. Stores it in the module and also returns it.

.. py:function:: run freqs ?statuscb?
   :noindex:

   the calibrated measurement sweep. Returns a

   dict with keys "ok" (1 if it ran to completion, 0 if cancelled) and "dataset" (an aa::calib dataset, see calib.tcl). Frequencies with no matching calibration point are corrected as 2H-1 (equivalent to an ideal, lossless bridge with no channel errors) rather than skipped, so a sweep started without calibrating still produces a usable, if less accurate, trace -- the GUI flags this in the status bar.

