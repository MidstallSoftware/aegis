# Clock Tile

Clock tiles generate divided clock signals from a reference clock and
distribute them to the fabric. Each clock tile provides four independent
outputs, each with its own divider, phase offset, and duty cycle control.

## Outputs

Each of the four outputs can be independently configured:

| Feature     | Range / Options                  |
|-------------|----------------------------------|
| Divider     | 1 to 256 (8-bit, divides by N+1) |
| Phase       | 0, 90, 180, or 270 degrees       |
| Duty cycle  | 50% toggle or single-cycle pulse |
| Enable      | Per-output enable bit            |

## Divider

Each output has an 8-bit counter that counts from 0 to the configured
divider value. This divides the reference clock frequency by
`(divider + 1)`, giving a range of divide-by-1 to divide-by-256.

## Phase Control

Phase offset shifts the output clock relative to the reference. The
offset is computed as a fraction of the divider period:

| Phase Select | Offset Cycles             |
|--------------|---------------------------|
| `00` (0)     | 0                         |
| `01` (90)    | divider / 4               |
| `10` (180)   | divider / 2               |
| `11` (270)   | divider / 2 + divider / 4 |

## Duty Cycle

In **50% duty mode** (`duty = 1`), the output toggles at the midpoint of
each period, producing a symmetric square wave.

In **pulse mode** (`duty = 0`), the output pulses high for one reference
clock cycle at the phase offset point and remains low otherwise.

## Lock Indicator

The `locked` output is asserted when all enabled clock outputs have
completed at least one full division cycle. This can be used for
synchronization or to gate downstream logic until clocks are stable.

## Configuration

| Bits        | Field         |
|-------------|---------------|
| `[0]`       | Global enable |
| `[8:1]`     | Divider 0 - 1 |
| `[16:9]`    | Divider 1 - 1 |
| `[24:17]`   | Divider 2 - 1 |
| `[32:25]`   | Divider 3 - 1 |
| `[34:33]`   | Phase 0       |
| `[36:35]`   | Phase 1       |
| `[38:37]`   | Phase 2       |
| `[40:39]`   | Phase 3       |
| `[41]`      | Enable 0      |
| `[42]`      | Enable 1      |
| `[43]`      | Enable 2      |
| `[44]`      | Enable 3      |
| `[45]`      | Duty 0        |
| `[46]`      | Duty 1        |
| `[47]`      | Duty 2        |
| `[48]`      | Duty 3        |

**Total: 49 bits**
