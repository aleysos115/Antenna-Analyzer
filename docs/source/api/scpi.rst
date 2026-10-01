``scpi.tcl``
============

Transport-agnostic SCPI client. Namespace: ``::aa::scpi``. Source: ``lib/scpi.tcl``.

.. py:function:: set_log_callback cb
   :noindex:

   cb is invoked as "{\*}$cb $direction $text" for every

   line sent or received, $direction one of TX RX ERR INFO. Used to drive the GUI's SCPI console tab; pass "" to silence logging.

.. py:function:: set_timeout ms
   :noindex:

   change the per-operation watchdog (default 4000 ms).

   Raise this for instruments that average many acquisitions per :SINGle.

.. py:function:: disconnect
   :noindex:

   close the channel if one is open. Safe to call repeatedly.

.. py:function:: connect_tcp host port ?timeout_ms?
   :noindex:

   open a raw TCP SCPI socket.

   Uses an async connect + writable-fileevent so a wrong host/port doesn't hang the caller for the OS-level TCP timeout (which can be a minute or more).

.. py:function:: connect_usbtmc devicefile
   :noindex:

   open a USBTMC character device, e.g.

   /dev/usbtmc0. Requires read/write permission on the device (see docs/installation.rst for the udev rule).

.. py:function:: query cmd
   :noindex:

   send cmd (normally ending in '?') and return the one-line reply.

.. py:function:: query_block cmd
   :noindex:

   send cmd and return the payload of an IEEE-488.2

   definite-length arbitrary block reply ("#<ndigits><length><bytes>") as a raw Tcl byte string, e.g. for `binary scan ... c\*` on waveform data.

.. py:function:: check_errors ?errquery?
   :noindex:

   drain the instrument's SCPI error queue (default

   command ":SYSTem:ERRor?"). Raises a Tcl error listing every non-zero entry found, so callers can just `check_errors` after a batch of setup commands.

