# Probe sequence

What `acd2300_i2c_probe()` does, in order:

1. Allocate the private data with `devm_kzalloc()`.
2. Get the supplies (`AVDD`, `DVDD`) and enable them.
3. Get the optional `reset` GPIO and pulse it low for 1 ms.
4. Set up the regmap (8-bit registers, 8-bit values).
5. Read `CHIP_ID`; fail with `-ENODEV` unless it is `0x23`.
6. Soft-reset, then `usleep_range(2000, 3000)`.
7. Register the ASoC component.

```c
ret = regmap_read(acd->regmap, ACD2300_CHIP_ID, &id);
if (ret)
	return dev_err_probe(dev, ret, "cannot read chip id\n");
if (id != ACD2300_CHIP_ID_VAL)
	return dev_err_probe(dev, -ENODEV, "unexpected chip id 0x%02x\n", id);
```

Errors on the way out disable the supplies through the devm action.
