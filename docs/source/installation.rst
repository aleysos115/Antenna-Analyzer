Installation
============

Requirements
------------

* **Tcl/Tk 8.6** or later. The app uses ``dict``, ``try``/``finally``, and
  non-blocking channels with ``vwait`` -- all core 8.6 features, no external
  Tcl packages required.
* A DSO2000-family oscilloscope with a built-in arbitrary waveform
  generator, reachable over LAN (raw SCPI socket) or USB (USBTMC, Linux
  only) -- or nothing at all, to start with :doc:`the mock instrument
  <testing>`.
* For development/screenshots only: Xvfb, ImageMagick, and Ghostscript are
  used by the test/screenshot scripts, not by the app itself.

Linux
-----

.. code-block:: console

   sudo apt-get install tcl tk tcllib

Tcllib isn't required by any ``lib/`` or ``gui/`` module (deliberately --
see :doc:`architecture`), but it's a harmless, common companion package and
the test suite's host environment has it installed.

**USBTMC permissions.** If you'll connect over USB rather than LAN, the
kernel's ``usbtmc`` driver creates a device node like
``/dev/usbtmc0`` that's normally root-owned. Add a udev rule so your user
can open it without ``sudo``:

.. code-block:: text

   /etc/udev/rules.d/99-usbtmc.rules
   SUBSYSTEM=="usbmisc", KERNEL=="usbtmc*", MODE="0666"

then ``sudo udevadm control --reload-rules && sudo udevadm trigger`` and
re-plug the instrument.

macOS
-----

.. code-block:: console

   brew install tcl-tk

Homebrew's ``tcl-tk`` is keg-only (it doesn't overwrite the system Tcl/Tk),
so launch the app with the Homebrew ``wish`` explicitly, e.g.
``/opt/homebrew/opt/tcl-tk/bin/wish8.6``. USBTMC is a Linux-specific kernel
driver; on macOS, use the LAN transport.

Windows
-------

Install `ActiveTcl <https://www.activestate.com/products/tcl/>`_ or
`Magicsplat Tcl/Tk <https://www.magicsplat.com/tcl-installer/>`_, both of
which bundle Tk. USBTMC is not available; use the LAN transport, or a
USB-to-LAN SCPI bridge if your instrument has no network port.

Verifying the install
----------------------

.. code-block:: console

   echo 'puts [info patchlevel]' | tclsh
   8.6.14
   echo 'package require Tk; puts [package present Tk]' | tclsh
   8.6.14

Getting the code
-----------------

This project is distributed as a plain directory tree (no build step, no
package manager) -- copy ``antenna_analyzer/`` wherever you like and run it
in place:

.. code-block:: console

   wish antenna_analyzer/src/bin/antenna_analyzer.tcl

See :doc:`quickstart` for what to do next.
