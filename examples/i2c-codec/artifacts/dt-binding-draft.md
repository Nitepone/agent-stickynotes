# Devicetree binding draft

```yaml
# SPDX-License-Identifier: GPL-2.0-only OR BSD-2-Clause
%YAML 1.2
---
$id: http://devicetree.org/schemas/sound/acme,acd2300.yaml#
title: ACME ACD2300 audio codec

properties:
  compatible:
    const: acme,acd2300
  reg:
    maxItems: 1
  clocks:
    maxItems: 1
  clock-names:
    const: mclk
  avdd-supply: true
  dvdd-supply: true
  reset-gpios:
    maxItems: 1
  "#sound-dai-cells":
    const: 0

required:
  - compatible
  - reg
  - avdd-supply
  - dvdd-supply
```

Open point: should `reset-gpios` be required? The dev board ties it high.
