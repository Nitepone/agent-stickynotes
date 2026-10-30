# ACD2300 register map

The ACD2300 is controlled over I2C (7-bit address `0x1a`, or `0x1b` with the
ADDR pin high) and carries audio over I2S. Registers are 8 bits wide.

| Reg  | Name        | Reset | Purpose                          |
|------|-------------|-------|----------------------------------|
| 0x00 | `CHIP_ID`   | 0x23  | Read-only identification         |
| 0x01 | `RESET`     | 0x00  | Write `0xA5` for a soft reset    |
| 0x02 | `PWR_CTRL`  | 0x01  | Analog and digital block power   |
| 0x03 | `CLK_CTRL`  | 0x00  | MCLK source and PLL enable       |
| 0x04 | `PLL_DIV`   | 0x10  | PLL feedback and reference dividers |
| 0x05 | `I2S_FMT`   | 0x02  | Format, word length, master/slave |
| 0x10 | `DAC_VOL_L` | 0xC0  | Left volume, 0.5 dB steps        |
| 0x11 | `DAC_VOL_R` | 0xC0  | Right volume, 0.5 dB steps       |
| 0x12 | `DAC_MUTE`  | 0x00  | Bit 0 left, bit 1 right          |
| 0x20 | `JACK_CTRL` | 0x00  | Jack-detect enable and debounce  |
| 0x21 | `IRQ_STAT`  | 0x00  | Interrupt status, clear on read  |

## Notes

- `CHIP_ID` reads `0x23` on every silicon revision seen so far.
- After a soft reset allow **2 ms** before the next register access.
- Registers `0x10`-`0x12` are volatile while the DAC ramps.
