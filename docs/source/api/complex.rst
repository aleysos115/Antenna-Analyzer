``complex.tcl``
===============

Complex-number arithmetic. Namespace: ``::aa::complex``. Source: ``lib/complex.tcl``.

.. py:function:: c re ?im?
   :noindex:

   construct a complex number. c 1 -- is the same as {1 0}.

.. py:function:: cadd a b
   :noindex:

   a + b

.. py:function:: csub a b
   :noindex:

   a - b

.. py:function:: cmul a b
   :noindex:

   a \* b

.. py:function:: cdiv a b
   :noindex:

   a / b

.. py:function:: cconj a
   :noindex:

   complex conjugate

.. py:function:: cabs a
   :noindex:

   magnitude \|a\|

.. py:function:: carg a
   :noindex:

   phase of a, radians, in (-pi, pi]

.. py:function:: cexp theta
   :noindex:

   unit phasor e^(i\*theta)

.. py:function:: c2polar a
   :noindex:

   {magnitude radians}

.. py:function:: polar2c mag theta
   :noindex:

   construct from magnitude + radians

