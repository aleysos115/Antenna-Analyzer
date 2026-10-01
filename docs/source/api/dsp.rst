``dsp.tcl``
===========

Phasor extraction (software lock-in). Namespace: ``::aa::dsp``. Source: ``lib/dsp.tcl``.

.. py:function:: mean y
   :noindex:

   arithmetic mean of a list of numbers

.. py:function:: hann_window n N
   :noindex:

   Hann window weight for sample index n of N (0 <= n < N)

.. py:function:: phasor y fs f
   :noindex:

   phasor y fs f

   Correlate a real-valued sample sequence y (sampled at fs Hz) against a complex exponential at frequency f, i.e. compute one bin of the DFT with a Hann window applied.  Returns {re im} of the resulting phasor.

   This is equivalent to (and far cheaper than) fitting f to a windowed FFT and reading off one bin: it costs O(N) instead of O(N log N) and needs no fixed record length or power-of-two size, which matters because the generator frequency and the scope's sample rate are not synchronized.

   The signal's DC component is removed first so that trigger offset, probe offset, or an imperfect null on channel 2 do not leak into the bin.

