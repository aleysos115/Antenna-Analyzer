Performance
============

A calibrated sweep takes longer than you might expect -- a 51-point sweep
with a full Short/Open/Load calibration is on the order of a minute. This
page explains why, so it reads as expected behavior rather than a bug.

The measured floor
---------------------

Profiling a single measurement point against ``mock/mockscope.tcl`` over a
loopback TCP socket (see ``tests/`` for the profiling approach):

.. list-table::
   :header-rows: 1
   :widths: 50 25

   * - Operation
     - Time
   * - A single trivial query (``*IDN?``)
     - ~44 ms
   * - :tcl:`::aa::driver::acquire` (one compound line, one reply)
     - ~69 ms
   * - :tcl:`::aa::driver::read_channel` (compound preamble query + binary
       block query)
     - ~84 ms
   * - One full :tcl:`::aa::sweep::measure_h` (acquire + both channels)
     - ~258 ms

Even an isolated, trivial, one-line query costs on the order of 40-45 ms.
That number is the signature of **Nagle's algorithm interacting with
delayed ACKs** over TCP -- a well-known, decades-old gotcha, and not
something fixable from pure Tcl: core Tcl sockets have no portable
``TCP_NODELAY`` option (disabling Nagle requires a C extension). It isn't
a bug in this app's networking code; it's close to the practical floor for
a request/response exchange over a plain Tcl socket.

What that means for a sweep
--------------------------------

Each measured point costs 5 SCPI round trips (one ``acquire``, two per
channel -- see :doc:`architecture`), so:

.. math::

   t_{\text{point}} \approx 5 \times 45\,\text{ms} \approx 225\,\text{ms}

which matches the measured ~258 ms closely enough that the difference is
just the mock's own processing time. A calibration sweep measures Short,
Open, and Load across the *entire* frequency list -- three full sweeps --
before the actual DUT sweep is a fourth, so:

.. math::

   t_{\text{total}} \approx 4 \times N \times t_{\text{point}}

For the GUI's default 51 points, that's of order a minute. The Sweep tab's
"Estimated:" line (:tcl:`::aa::gui::update_time_estimate`) uses this same
~0.25 s/point constant to give a rough number before you commit to a run;
it's deliberately conservative and does not gate the Run button.

Why not just optimize it away
-----------------------------------

A few things were tried and kept; one thing was tried and deliberately
*not* kept:

* **Compounding commands** (see :doc:`scpi_reference`) cut real,
  significant time: an early version issued ``set_freq``, ``set_timebase``,
  and ``:SINGle`` as three separate writes before the first mock run
  actually got timed, which combined with the mock server's own output
  buffering into multi-second stalls per sweep. Folding them into one
  compound line per logical operation fixed that class of problem
  entirely, and is kept.
* **A real Tcl ``coroutine``** was tried early on, to ``yield`` the sweep
  loop after each point. It turned out to add a second cooperative-
  multitasking mechanism on top of one ``scpi.tcl`` already has (its
  ``vwait``-based waits already re-enter Tk's event loop on every network
  wait -- see :doc:`architecture`), without buying any additional
  responsiveness. It was removed in favor of the current plain-proc sweep.
* **Disabling Nagle** was considered and set aside: it would require a C
  extension (e.g. ``critcl``), which this project deliberately avoids (see
  ``docs/scpi_reference``'s emphasis on plain, portable Tcl). For a
  request/response instrument-control protocol -- as opposed to, say,
  streaming -- the extra ~40 ms per round trip is a real cost but not one
  worth a build-toolchain dependency to remove.
* **Reducing round trips per point further** would mean asking a real
  instrument to return both channels' waveforms from a single query, which
  is not generally available across the DSO2000 family's documented
  command set (and would make :doc:`the mock <testing>` diverge from
  realistic instrument behavior, defeating its purpose). Five round trips
  per point is treated as close to the practical floor for this
  measurement approach.

If your real instrument is on a LAN with higher latency than loopback (a
plausible few milliseconds vs. loopback's effectively-zero transit time),
expect sweep time to scale accordingly -- the 40-45 ms floor above is a
*minimum*, not a ceiling.
