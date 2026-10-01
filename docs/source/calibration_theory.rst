Calibration Theory
===================

This page derives the one-port Short/Open/Load (SOL) correction
implemented in :tcl:`::aa::calib::sol_correct`, and explains a numerical
pitfall the straightforward textbook formula has that the implementation
deliberately avoids.

The error model
-----------------

The raw ratio :math:`M = V_2/V_1` the test head produces is **not** the
true reflection coefficient :math:`\Gamma` of whatever is connected at the
DUT reference plane. Cable length, probe capacitance, and channel
gain/phase mismatch between CH1 and CH2 all distort it. But every one of
those error sources is *linear*, and a linear two-port error network
sitting between an ideal reference plane and an ideal measurement maps
:math:`\Gamma` to :math:`M` as a **bilinear (Mobius) transform**:

.. math::

   M(\Gamma) = \frac{a\,\Gamma + b}{c\,\Gamma + d}

for some complex :math:`a, b, c, d` that depend on frequency and on
everything physically between the reference plane and the scope's ADCs --
but, crucially, not on *what's connected* at the reference plane. That's
what makes calibration possible at all: measure :math:`M` for three
*known* values of :math:`\Gamma`, solve for (a scaled version of) the four
unknowns, and invert the map for every subsequent measurement.

Solving for the Mobius map
------------------------------

Use the three standards -- Short (:math:`\Gamma=-1`), Open
(:math:`\Gamma=+1`), Load (:math:`\Gamma=0`) -- giving three equations:

.. math::

   M_s = \frac{-a+b}{-c+d}, \qquad
   M_o = \frac{a+b}{c+d}, \qquad
   M_l = \frac{b}{d}

Four unknowns, three equations: :math:`a,b,c,d` are determined only up to
one overall complex scale (expected -- multiplying numerator and
denominator of a Mobius transform by the same constant doesn't change the
map). Fix the scale with :math:`d=1`. Then :math:`M_l = b \Rightarrow b =
M_l`, and the remaining two equations reduce to one linear equation for
:math:`c`:

.. math::

   c = \frac{M_o + M_s - 2 M_l}{M_s - M_o}

with :math:`a = M_o(1+c) - M_l`. Inverting :math:`M = (a\Gamma+b)/(c\Gamma+d)`
for :math:`\Gamma` and substituting :math:`b=M_l,\ d=1` gives the
correction actually implemented:

.. math::

   \Gamma(M) = \frac{M - M_l}{(M_o - M_l) + c\,(M_o - M)}, \qquad
   c = \frac{M_o + M_s - 2 M_l}{M_s - M_o}

This is exactly :tcl:`::aa::calib::sol_correct`'s body, line for line.

A numerical pitfall in the textbook form
---------------------------------------------

Most references present the inversion as a **cross-ratio**: since a Mobius
transform preserves cross-ratios, :math:`(M; M_s, M_o, M_l)` equals
:math:`(\Gamma; -1, 1, 0)`, usually written as

.. math::

   R = \frac{(M - M_l)(M_o - M_s)}{(M - M_s)(M_o - M_l)}, \qquad
   \Gamma = \frac{R - 1}{R + 1}

This is algebraically equivalent to the boxed formula above *almost*
everywhere -- but it has a removable singularity at :math:`M = M_s`: the
denominator :math:`(M - M_s)` is exactly zero there, so evaluating it
naively raises a division-by-zero, even though the correct answer
(:math:`\Gamma = -1`) is perfectly well defined as a limit (:math:`R \to
\infty`, and :math:`R/(R+1) \to 1`... worked through fully,
:math:`(R-1)/(R+1) \to -1`).

That is not a corner case you can shrug off: **re-measuring the short
standard itself**, immediately after calibrating, is a completely standard
calibration-quality check (see :doc:`schematics`) -- and it is exactly the
input that trips the textbook formula's division by zero. The
:math:`c`-based form above has no such singularity (its denominator at
:math:`M=M_s` evaluates to :math:`M_o - M_l`, generically nonzero), so
``sol_correct`` uses it instead. Both forms were cross-checked numerically
against each other away from the singular point while developing this
module -- see the ``calib-3.*`` cases in ``tests/unit.test``, including one
that specifically re-measures the short standard and asserts the result is
finite and equals :math:`-1`.

From Gamma to impedance, SWR, and return loss
--------------------------------------------------

Given the corrected :math:`\Gamma` and a reference impedance :math:`Z_0`
(the standard antenna-analyzer convention is :math:`50\,\Omega`):

.. math::

   Z = Z_0\,\frac{1+\Gamma}{1-\Gamma}, \qquad
   \mathrm{SWR} = \frac{1+|\Gamma|}{1-|\Gamma|}, \qquad
   \mathrm{RL} = -20\log_{10}|\Gamma|\ \mathrm{dB}

:tcl:`::aa::calib::z_of_gamma` returns ``{Inf 0}`` rather than raising when
:math:`\Gamma \to 1` (an ideal open truly has infinite impedance -- that's
not a bug to work around, it's the physically correct answer), and
:tcl:`::aa::calib::swr_of_gamma`/``rl_of_gamma`` clamp :math:`|\Gamma|`
just shy of 1 and just above 0 respectively so a short or a very good match
produces a large finite number instead of an error.

What calibration *can't* fix
--------------------------------

The error model above assumes the error network is the same linear system
for the calibration standards and for the DUT measurement. It is not the
same system if:

* the standards and the DUT are connected with different lead lengths or
  geometry (see :doc:`schematics`'s build notes), or
* ambient RF or static couples into the measurement differently between
  calibration and the actual antenna sweep (an antenna, unlike a short/
  open/load standard, is an antenna), or
* conditions drift between calibrating and sweeping -- V/div, probe
  setting, timebase, cable. ``gui/app.tcl`` applies the same channel
  settings for both, but a *manual* change to those settings between
  calibrating and sweeping invalidates the calibration silently; nothing
  currently detects that for you.
