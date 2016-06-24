# hamnet-cc1101

This software allows a CC1101 chip to be used in a Beaglebone black as an ethernet device (tap interface).

INSTRUCTIONS
--------------

1. You need a CC1101 chip or module and a Beaglebone black.
2. The CC1101 chip or module has to be connected to the Beaglebone as follows:
    CS - P9_27
    MISO - P9_28
    MOSI - P9_29
    CLK - P9_30
    GDO0 - P9_31
  If your modules has a PA that is enabled with an active high signal, you can connect the GDO2
  pin on the CC1101 to the PA enable pin.
3. Run make
4. cp BB-HAMNET-CC1101-00A0.dtbo /lib/firmware
5. echo BB-HAMNET-CC1101 > /sys/devices/bone_capemgr.9/slots
6. Run ./hamnet-cc1101
7. A tap interface (usually tap0) is created. Set this interface up for IP traffic or bridge it

Currently, the code uses 128kbps MSK at 434.000MHz. This can be changed by modyfing the values of the
registers in hamnet-cc1101.p. Texas Instruments has a software tool that helps to choose optimal register values.
