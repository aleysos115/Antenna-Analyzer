Troubleshooting
================

"Connection failed" / timeout when connecting
---------------------------------------------------

* **TCP**: confirm the instrument's SCPI LAN server is enabled and on the
  port you typed (often, but not always, 5025), and that nothing else
  (another instance of this app, a terminal session) already holds that
  socket. :tcl:`::aa::scpi::connect_tcp` fails fast (a few seconds) rather
  than hanging, so a long wait before the error dialog usually means a
  firewall is dropping packets rather than actively refusing the
  connection.
* **USBTMC**: check the device file exists (``ls /dev/usbtmc*``) and is
  readable/writable by your user -- see the udev rule in
  :doc:`installation`. If the device file doesn't appear at all, confirm
  the kernel's ``usbtmc`` module is loaded (``lsmod | grep usbtmc``) and
  that the instrument enumerates as a USB TMC device
  (``lsusb``/``dmesg`` after plugging in).

A sweep raises an error partway through
---------------------------------------------

The error dialog's text comes straight from wherever it was raised --
``driver.tcl``, ``scpi.tcl``, or the instrument's own error queue via
:tcl:`::aa::scpi::check_errors` -- so read it before assuming it's
mysterious:

* ``SCPI: read timeout (no reply)`` almost always means a mnemonic your
  instrument doesn't recognize, or recognizes differently -- see
  :doc:`scpi_reference` on adapting the driver profile, and try the exact
  command by hand in the **SCPI Console** tab first.
* ``driver: CH1 waveform length mismatch`` means the point count the
  instrument's ``:WAVeform:PREamble?`` reported doesn't match what
  actually arrived in the ``:WAVeform:DATA?`` block -- a sign the
  acquisition settings (timebase, record length) changed between those two
  queries, which shouldn't happen within one ``read_channel`` call unless
  something else (another program, a front-panel knob) is also talking to
  the instrument at the same time.
* A SCPI error-queue message (anything starting with a negative number, in
  the ``-1xx``/``-2xx`` SCPI standard error range) came from the
  instrument itself rejecting a command -- usually an out-of-range value
  for your specific hardware (amplitude, timebase) rather than a bug here.

The GUI freezes during a sweep
------------------------------------

It shouldn't, by design (see :doc:`architecture`'s explanation of the
``vwait``-based async I/O) -- with one specific exception: **USBTMC mode
runs with plain blocking reads**, because the Linux ``usbtmc`` character
device doesn't reliably support the ``fileevent``/``poll()`` mechanism the
TCP transport relies on for responsiveness. If you need the GUI to stay
responsive during a slow acquisition and your instrument has a LAN SCPI
server, prefer the TCP transport.

If the GUI is unresponsive over TCP, it's more likely stuck inside a
single very slow instrument operation than genuinely hung -- raise
:tcl:`::aa::scpi::set_timeout` if your instrument needs longer than the
4-second default for a ``:SINGle`` acquisition (e.g. with heavy averaging
configured on the instrument itself), so a slow-but-working reply doesn't
get mistaken for a wedged connection.

Calibration produces nonsensical values (negative resistance, reflection magnitude > 1)
---------------------------------------------------------------------------------------------

This means the three calibration standards weren't actually different
when measured -- almost always because the physical standard wasn't
swapped between the wizard's three prompts (easy to do if you're also
driving the mock instrument's ``:SIMulate:DUT`` by hand for testing, see
:doc:`testing`'s note on exactly this mistake during development).
Re-calibrate, and actually change what's connected at each of the three
prompts.

Sweep seems slow
--------------------

It's probably not a bug -- read :doc:`performance` before investigating
further. A 50-ish-point calibrated sweep taking the better part of a
minute is expected behavior given the per-SCPI-round-trip floor plain Tcl
sockets have, not a sign something's wrong.

The menu bar doesn't show up in a screenshot / under a window manager-less X session
------------------------------------------------------------------------------------------

Cosmetic, and specific to this documentation's headless screenshot
pipeline (Xvfb with no window manager running) -- see :doc:`testing`. The
**File**/**Instrument**/**Help** menus function normally in an ordinary
desktop session; this doesn't affect the app itself.

Something else
------------------

Check the **SCPI Console** tab's log -- every command sent and every reply
received is right there, color-coded, which is usually enough to tell
whether the problem is in this app's logic or in how the instrument
responded to a specific command.
