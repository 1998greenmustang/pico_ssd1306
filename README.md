# SSD1306 Driver for RPI Pico in Nim

Requires [picostdlib](https://github.com/EmbeddedNim/picostdlib)

## Installation

```shell
nimble install https://github.com/1998greenmustang/pico_ssd1306/
```

## Hello World Example

```nim
import picostdlib/[gpio, i2c]
import pico_ssd1306

# setup i2c0 or i2c1, see pin out diagram for the pins you want to use
setupI2c(i2c1, 26.Gpio, 27.Gpio, 200000)

# I2cInst, width, height, address, external_vcc
# note: my setup process is probably incorrect atm
var disp = createDisplay(i2c1, 128, 64, 0x3c, false)

disp.drawString(
  (x: 10.uint, y: 26.uint).Point, # maybe the middle of my 128x64 screen
  "Hello, world!"
)
disp.show()
```

## Thanks/Resources I used

makerportal's [rpi-pico-ssd1306](https://github.com/makerportal/rpi-pico-ssd1306): driver in MicroPython

dashcr's [pico-ssd1306](https://github.com/daschr/pico-ssd1306/): driver in C

lynniemagoo's [old-font-pack](https://github.com/lynniemagoo/oled-font-pack/): fonts for OLED displays

micropython (and their framebuf [implementation](https://github.com/micropython/micropython/blob/8995a291e05aef6c2ab1a24647355eae87dca391/extmod/modframebuf.c))
