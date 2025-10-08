import picostdlib/[i2c]
import sequtils
import math
import ./font

type Point* = tuple
    x: uint
    y: uint

type AntialiasedLine = object
    low: uint
    high: uint
    steps: uint

iterator items(range: AntialiasedLine): float =
    let step_val = if range.steps > range.high - range.low:
                       (range.high.float - range.low.float) / range.steps.float
                   else: 1.0
    var i = range.low.float
    while i <= range.high.float:
        yield i
        i += step_val

type SetConstants* = enum 
    SET_CONTRAST = 0x81
    SET_ENTIRE_ON = 0xA4
    SET_NORM_INV = 0xA6
    SET_DISP = 0xAE
    SET_MEM_ADDR = 0x20
    SET_COL_ADDR = 0x21
    SET_PAGE_ADDR = 0x22
    SET_DISP_START_LINE = 0x40
    SET_SEG_REMAP = 0xA0
    SET_MUX_RATIO = 0xA8
    SET_COM_OUT_DIR = 0xC0
    SET_DISP_OFFSET = 0xD3
    SET_COM_PIN_CFG = 0xDA
    SET_DISP_CLK_DIV = 0xD5
    SET_PRECHARGE = 0xD9
    SET_VCOM_DESEL = 0xDB
    SET_CHARGE_PUMP = 0x8D

type Display* = object
    i2c_i*: I2cInst 
    external_vcc*: bool
    width*, height*, pages*, address*: uint
    bufsize*: uint
    buffer*: seq[byte]

proc write*(disp: var Display, command: uint8) =
    let cmd: array[2, uint8] = [0x80, command]
    disp.i2c_i.writeBlocking(
        disp.address.I2cAddress,
        cmd,
        false
    )

proc write_buffer*(disp: var Display) =
    disp.i2c_i.writeBlocking(
        disp.address.I2cAddress,
        concat(@[0x40.byte], disp.buffer),
        false
    )

proc show*(disp: var Display) =
    let x_min: uint8 = 0
    let x_max = (disp.width - 1).uint8
    disp.write(SET_COL_ADDR.uint8)
    disp.write(x_min)
    disp.write(x_max)
    disp.write(SET_PAGE_ADDR.uint8)
    disp.write(0)
    disp.write((disp.pages - 1).uint8)
    disp.write_buffer()
    

proc powerOff*(disp: var Display) =
    disp.write(SET_DISP.uint8 or 0x00)


proc powerOn*(disp: var Display) =
    disp.write(SET_DISP.uint8 or 0x01)

proc setContrast*(disp: var Display, contrast: uint8) =
    disp.write(SET_CONTRAST.uint8)
    disp.write(contrast)

proc invert*(disp: var Display, invert: uint8) =
    disp.write(SET_NORM_INV.uint8 or (invert and 1))

    
proc drawPixel*(disp: var Display, x: uint, y: uint, col: uint = 1) =
    if x >= disp.width or y >= disp.height: return

    # im not sure what "stride" is or what value it should be
    let stride = disp.width
    let index = (y shr 3) * stride + x
    let offset = y and 0x07;

    # no clue what this even is but
    # does col even stand for column?
    
    # (col != 0) << offset
    let column = (col != 0).byte shl offset
    # ~(0x01 << offset)
    let main_thing = not (0x01 shl offset).byte
    
    disp.buffer[index] = (disp.buffer[index] and main_thing) or column;

proc drawPixel*(disp: var Display, point: Point, col: uint = 1) =
    disp.drawPixel(point.x, point.y, col)

proc drawLine*(disp: var Display, x1: uint, x2: uint, y1: uint, y2: uint, antialias_steps: uint = 25) =
    if x1 == x2:
        for y in y1..y2:
            disp.drawPixel(x1, y)
        return
    
    let m = ((y2 - y1).float / (x2 - x1).float)
    let b = round(y1.float - m * x1.float)
    proc y(x: float): uint = round(m * x + b).uint
    for x in AntialiasedLine(low: x1, high: x2, steps: antialias_steps):
        disp.drawPixel(round(x).uint, y(x))

proc drawLine*(disp: var Display, first_point: Point, second_point: Point, antialias_steps: uint = 25) =
    let (x1, x2) = if second_point.x < first_point.x: (second_point.x, first_point.x)
                   else: (first_point.x, second_point.x)
    let (y1, y2) = if second_point.y < first_point.y: (second_point.y, first_point.y)
                   else: (first_point.y, second_point.y)
    disp.drawLine(
        x1, x2, y1, y2, antialias_steps
    )

proc drawRect*(disp: var Display, first_point: Point, second_point: Point, antialias_steps: uint = 25) =
    let third_point = (x: first_point.x, y: second_point.y).Point;
    let fourth_point = (x: second_point.x, y: first_point.y).Point;
    disp.drawLine(first_point, third_point, antialias_steps)
    disp.drawLine(first_point, fourth_point, antialias_steps) 
    disp.drawLine(second_point, third_point, antialias_steps)
    disp.drawLine(second_point, fourth_point, antialias_steps)

proc drawRect*(disp: var Display, point: Point, scale: uint) =
    disp.drawLine(
        point,
        (x: point.x + scale, y: point.y + scale)
    )

proc drawCircle*(disp: var Display, point: Point, radius: uint, antialias_steps: uint = 25) =
    let (h, k) = point
    proc y(x: float): tuple[y1, y2: uint] =
        let x_h = x - h.float
        let equation = round(sqrt(radius.float * radius.float - (x_h * x_h))).uint
        return (y1: k + equation, y2: k - equation)

    for x in AntialiasedLine(low: h - radius, high: h + radius, steps: antialias_steps):
        let (y1, y2) = y(x)
        disp.drawPixel(round(x).uint, y1)
        disp.drawPixel(round(x).uint, y2)

proc drawChar*(disp: var Display, point: Point, c: char) =
    let (height, width) = (oled_5x7.height, oled_5x7.width)
    let c_index = oled_5x7.lookup.find(c) * 5
    for w in 0..width - 1:
        # each byte is a column of 7 pixels
        var line = oled_5x7.data[c_index.uint + w]
        for y in point.y..point.y + height:
            if (line and 1) > 0:
                disp.drawPixel((point.x + w.uint, y))
            # scan over vertical column
            line = line shr 1

proc drawString*(disp: var Display, point: Point, s: string) =
    var x = point.x
    for c in s:
        disp.drawChar((x, point.y), c)
        x += 6

proc drawImage*(disp: var Display, data: seq[byte], point: Point, width: uint, height: uint) =
    var (w, h) = (0.uint, 0.uint)
    # each bit will be a pixel
    for b in data:
        var byt = b
        for i in 0..7:
            if (byt and 1) > 0:
                disp.drawPixel((point.x + w), (point.y + h))
            w += 1
            if w >= width:
                h += 1
                w = 0
            byt = byt shr 1

proc createDisplay*(i2c_i: var I2cInst, width: uint8, height: uint8, address: uint8, external_vcc: bool): Display =
    let pages = round(height.float / 8.0).uint
    let bufsize = pages * width
    var disp = Display(
        i2c_i: i2c_i,
        width: width,
        height: height,
        address: address,
        pages: pages,
        external_vcc: external_vcc,
        bufsize: bufsize,
        buffer: newSeq[byte](bufsize)
    )

    let startup = [
        SET_DISP.uint8,
        SET_DISP_CLK_DIV.uint8,
        0x80,
        SET_MUX_RATIO.uint8,
        height - 1,
        SET_DISP_OFFSET.uint8,
        0x00,
        SET_DISP_START_LINE.uint8,
        # charge pump
        SET_CHARGE_PUMP.uint8,
        (if external_vcc: 0x10 else: 0x14),
        SET_SEG_REMAP.uint8 or 0x01,           # column addr 127 mapped to SEG0
        SET_COM_OUT_DIR.uint8 or 0x08,         # scan from COM[N] to COM0
        SET_COM_PIN_CFG.uint8,
        (if width > (2 * height): 0x02
        else: 0x12),
        # display
        SET_CONTRAST.uint8,
        0xff,
        SET_PRECHARGE.uint8,
        (if external_vcc: 0x22 else: 0xF1),
        SET_VCOM_DESEL.uint8,
        0x30,                           # or 0x40?
        SET_ENTIRE_ON.uint8,                  # output follows RAM contents
        SET_NORM_INV.uint8,                   # not inverted
        SET_DISP.uint8 or 0x01,
        # address setting
        SET_MEM_ADDR.uint8,
        0x00,  # horizontal
    ]
    
    for cmd in startup:
        disp.write(cmd)

    disp.show()
    return disp

