Major components:
- ice40 Ultraplus breakout board
- BOOSTXL-DRV8323RX
- 2x Digilent PMOD-AD1 boards (each with 2xAD7476A)
- AS5600 magnetic encoder configured as analog output
- 1x BLDC 3 phase motor

Current sense connections:
-  AD1.A0 = ISENB
-  AD1.A1 = ISENC
-  AD2.A0 = ISENA

Encoder connection:
-  AD2.A1 = AS5600.OUT

Digital connections:
- SPI.SCK = AD1.CLK = AD2.CLK
- SPI.SS = AD1.SS = AD2.SS
- 37A = AD1.D1
- 36B = AD1.D0
- 39A = AD2.D1
- 38B = AD2.D0

- 22A = INHA
- 23B = INLA
- 24A = INHB
- 25B = INLB
- 29B = INHC
- 31B = INLC
- 20A = SDI
- 18A = SDO
- 16A = nSCS
- 13B = SCLK

