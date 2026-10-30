# Clocking notes

The codec needs a bit clock derived from MCLK. With a 12.288 MHz MCLK the
common rates are exact; 44.1 kHz needs the PLL.

| Rate (Hz) | MCLK (MHz) | PLL | `PLL_DIV` |
|-----------|-----------:|-----|-----------|
| 48000     | 12.288     | off | `0x10`    |
| 96000     | 12.288     | off | `0x20`    |
| 44100     | 12.288     | on  | `0x1b`    |
| 88200     | 12.288     | on  | `0x2b`    |

## To do

- `set_sysclk()` should reject an MCLK outside 8-27 MHz.
- `hw_params()` picks the divider from the table above and enables the PLL only when needed.
- Check lock: the PLL lock bit in `IRQ_STAT` should be set within 5 ms.
