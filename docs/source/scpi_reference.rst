.. _scpi-reference:

SCPI Reference
===============

Transports
----------

``lib/scpi.tcl`` exposes exactly two ways to open a connection, and
everything above it (``driver.tcl`` and up) is written against the same
five calls (``connect_tcp``/``connect_usbtmc``, ``write``, ``query``,
``query_block``, ``disconnect``) regardless of which one is in use:

.. list-table::
   :header-rows: 1
   :widths: 20 40 40

   * - Transport
     - How
     - Notes
   * - ``TCP``
     - :tcl:`::aa::scpi::connect_tcp host port`
     - Raw SCPI socket (the common "SCPI raw" port, often 5025). Async
       connect with a watchdog timeout, so a wrong host/port fails fast
       instead of hanging on the OS-level TCP timeout.
   * - ``USBTMC``
     - :tcl:`::aa::scpi::connect_usbtmc devicefile`
     - Linux only (``/dev/usbtmcN``). Falls back to synchronous blocking
       reads -- see the caveat in :doc:`architecture` and
       :doc:`troubleshooting`.

Every read, on either transport, is guarded by a watchdog
(:tcl:`::aa::scpi::set_timeout`, default 4000 ms): a wrong mnemonic that
gets no reply raises a Tcl error instead of hanging the app.

The mnemonic profile
------------------------

``driver.tcl`` keeps every literal SCPI command string in one place -- the
``profile`` array -- specifically so that adapting this app to a real
instrument whose command set differs from the defaults below is a
one-file, one-array edit, not a hunt through ``sweep.tcl`` or ``app.tcl``.

.. list-table::
   :header-rows: 1
   :widths: 25 40 35

   * - Profile key
     - Default command
     - Used by
   * - ``idn``
     - ``*IDN?``
     - :tcl:`::aa::driver::idn`
   * - ``reset`` / ``clear``
     - ``*RST`` / ``*CLS``
     - :tcl:`::aa::driver::reset`
   * - ``opc_query``
     - ``*OPC?``
     - :tcl:`::aa::driver::acquire` (acquisition-complete sync point)
   * - ``err_query``
     - ``:SYSTem:ERRor?``
     - :tcl:`::aa::scpi::check_errors`
   * - ``src_freq_set`` / ``src_freq_query``
     - ``:SOURce:FREQuency %s`` / ``?``
     - :tcl:`::aa::driver::set_freq`, :tcl:`::aa::driver::acquire`
   * - ``src_ampl_set``
     - ``:SOURce:AMPLitude %s``
     - :tcl:`::aa::driver::configure_source`
   * - ``src_out_set``
     - ``:SOURce:OUTPut %s``
     - :tcl:`::aa::driver::configure_source`
   * - ``chan_scale_set``
     - ``:CHANnel%d:SCALe %s``
     - :tcl:`::aa::driver::configure_channel`
   * - ``chan_probe_set``
     - ``:CHANnel%d:PROBe %s``
     - :tcl:`::aa::driver::configure_channel`
   * - ``chan_coupling_set``
     - ``:CHANnel%d:COUPling %s``
     - :tcl:`::aa::driver::configure_channel`
   * - ``tbase_scale_set``
     - ``:TIMebase:SCALe %s``
     - :tcl:`::aa::driver::set_timebase`, :tcl:`::aa::driver::acquire`
   * - ``acquire_single``
     - ``:SINGle``
     - :tcl:`::aa::driver::acquire`
   * - ``wav_source_set``
     - ``:WAVeform:SOURce CHANnel%d``
     - :tcl:`::aa::driver::read_channel`
   * - ``wav_preamble_query``
     - ``:WAVeform:PREamble?``
     - :tcl:`::aa::driver::read_channel`
   * - ``wav_data_query``
     - ``:WAVeform:DATA?``
     - :tcl:`::aa::driver::read_channel`

These are written in the *generic* SCPI style common to the DSO2000
family's documented command set and match ``mock/mockscope.tcl`` exactly
(see :doc:`testing`). **They have not been verified against a specific
real DSO2000 unit's programmer's manual** -- treat them as a well-formed
starting point, not a guarantee. Before pointing this at real hardware:

1. Open your instrument's programmer's manual and find the equivalent
   command for each row above.
2. Call :tcl:`::aa::driver::load_profile` with only the keys that differ,
   e.g.:

   .. code-block:: tcl

      ::aa::driver::load_profile {
          wav_data_query  :WAVeform:FETCh?
          acquire_single  :RUN:SINGle
      }

   (``load_profile`` rejects unknown keys, so a typo'd key name fails
   loudly rather than silently doing nothing.)
3. Use the **SCPI Console** tab (:doc:`gui_guide`) to try commands by hand
   against the real instrument before trusting a full sweep to them.

Every value ``%s``/``%d`` substitutes is produced by Tcl's `format`, so a
command needing a different numeric style (e.g. forcing scientific
notation) can be changed by editing the format string itself.

Why compound commands
-------------------------

:tcl:`::aa::driver::acquire` and :tcl:`::aa::driver::read_channel` each
join several profile entries with ``;`` into a single write, rather than
sending them as separate commands. This isn't just an optimization -- see
:doc:`performance` for the measured effect -- it's also how the SCPI
standard expects a program message to look: multiple commands separated by
``;`` within one program message are processed in order by the
instrument, and ``*OPC?`` at the end of a compound line is the standard
synchronization idiom for "tell me when everything before this is done."

Error handling
-----------------

:tcl:`::aa::scpi::check_errors` drains the instrument's SCPI error queue
(default query ``:SYSTem:ERRor?``) and raises a single Tcl error listing
every non-zero entry it finds, up to 25 entries deep. ``gui/app.tcl`` calls
it right after applying sweep settings (amplitude, channel scale/probe/
coupling) and before starting a sweep or calibration, so a rejected
setting (out-of-range amplitude, unsupported coupling, ...) surfaces as a
dialog immediately instead of silently producing a bad sweep.

The SCPI Console tab's log (color-coded ``TX``/``RX``/``ERR``/``INFO``) is
driven by :tcl:`::aa::scpi::set_log_callback`, which any code -- not just
the GUI -- can hook to observe every command and reply.
