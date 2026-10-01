``driver.tcl``
==============

Semantic instrument operations + mnemonic profile. Namespace: ``::aa::driver``. Source: ``lib/driver.tcl``.

.. py:function:: load_profile overrides
   :noindex:

   overlay replacement mnemonics onto the default

   profile, e.g. after reading a JSON/Tcl-dict file shipped for a specific instrument. Unknown keys are rejected so a typo doesn't silently do nothing.

.. py:function:: idn
   :noindex:

   return the instrument's \*IDN? response

.. py:function:: reset
   :noindex:

   send \*RST;\*CLS

.. py:function:: configure_source amplitude_vpp on
   :noindex:

   set the built-in generator's amplitude

   and output state (frequency is set per-point by set_freq, below).

.. py:function:: set_freq hz
   :noindex:

   set the generator frequency for the next acquisition

.. py:function:: acquire hz s_per_div
   :noindex:

   set frequency + timebase and trigger one

   acquisition, waiting for it to finish. Sent as a single compound SCPI line (one round trip, one \*OPC? reply) rather than three separate writes and a query: on a loopback or LAN socket each unacknowledged small write is a fresh TCP segment, and without Nagle disabled (plain Tcl sockets have no portable way to set TCP_NODELAY) a run of them can each stall for a delayed-ACK interval. Compounding is also simply how SCPI is meant to be driven -- see sweep.tcl's design note and docs/scpi_reference.rst.

.. py:function:: configure_channel ch scale probe coupling
   :noindex:

   vertical setup for CH1/CH2

.. py:function:: set_timebase s_per_div
   :noindex:

   horizontal scale

.. py:function:: single_and_wait
   :noindex:

   trigger one acquisition and block (Tk-safely, see

   scpi.tcl) until it completes, using \*OPC? as the synchronization point.

.. py:function:: read_channel ch
   :noindex:

   download one channel's most recent acquisition.

   Returns {dt_seconds samples} where samples is a list of signed integer ADC codes (the caller applies volts/code itself if absolute volts matter; the phasor extraction in dsp.tcl only needs a signal proportional to volts).

