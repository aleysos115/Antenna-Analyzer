``calib.tcl``
=============

SOL calibration, Gamma conversions, dataset export. Namespace: ``::aa::calib``. Source: ``lib/calib.tcl``.

.. py:function:: z_of_gamma gamma ?z0?
   :noindex:

   complex impedance for a reflection coefficient.

   An ideal open (Gamma==1) has no finite impedance; that case returns {Inf 0} rather than raising a division-by-zero error, so a sweep that lands exactly on it doesn't abort.

.. py:function:: swr_of_gamma gamma
   :noindex:

   voltage standing wave ratio (>= 1)

.. py:function:: rl_of_gamma gamma
   :noindex:

   return loss in dB (positive number, larger = better)

.. py:function:: new_dataset
   :noindex:

   empty dataset dict

.. py:function:: add_point datasetVar f gamma
   :noindex:

   append one swept point (call by upvar name)

.. py:function:: write_s1p path dataset ?z0?
   :noindex:

   Touchstone version 1, single-port, RI format

   Format reference: freq-unit S-parameter data-format R z0, one row per frequency: "freq  re  im".  Any S1P-reading tool (including most antenna analyzer / NanoVNA-Saver-style software) can load this for cross-checking.

.. py:function:: write_csv path dataset ?z0?
   :noindex:

   human-readable sweep table

