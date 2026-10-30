# I2C bring-up log

Dev board: i.MX8 evaluation kit, codec on `i2c3`.

## Results

1. `i2cdetect -y 3` shows `1a`. The codec ACKs.
2. `i2cget -y 3 0x1a 0x00` returns `0x23`: the chip ID matches.
3. Writing `0xA5` to `RESET` and reading `CHIP_ID` straight away returned
   `0xff`. Waiting 2 ms fixes it, so the driver must sleep after a reset.
4. The bus runs reliably at 400 kHz. At 1 MHz about one transfer in a
   hundred fails, so the binding should cap `clock-frequency` at 400 kHz.

## Open questions

- Does the datasheet allow the reset GPIO to be released before the supplies are stable?
- Which supply powers the I2C pull-ups on the dev board?
