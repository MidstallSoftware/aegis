# DSP Tile

DSP tiles provide hardware multiply-accumulate (MAC) units distributed
across the fabric in dedicated columns. Each DSP tile performs an 18x18
unsigned multiplication with optional accumulation or addition.

## Operands

| Operand | Width  | Source                                                  |
|---------|--------|---------------------------------------------------------|
| A       | 18 bits | North routing tracks `[17:0]`                          |
| B       | 18 bits | West routing tracks `[17:0]`                           |
| C       | varies  | North tracks `[tracks-1:18]`, zero-extended to 36 bits |

The result is a 36-bit value driven onto the south routing tracks. All
other directions output zero.

## Operation Modes

The DSP supports four modes, selected by config bits `[3:2]`:

| Mode | Config `[3:2]` | Operation                      |
|------|----------------|--------------------------------|
| 0    | `00`           | `result = A * B`               |
| 1    | `01`           | `result = A * B + C`           |
| 2    | `10`           | `result = A * B + accumulator` |
| 3    | `11`           | Reserved (defaults to `A * B`) |

Mode 1 adds an external constant (provided via the north tracks). Mode 2
feeds the previous result back through the accumulator for iterative MAC
operations.

## Pipeline Registers

The DSP has two optional pipeline stages controlled by configuration:

**Enable** (config bit `[0]`): gates both the accumulator and the output
register. When enabled, both registers latch the raw result on each
clock edge. When disabled, neither register updates.

**Output register select** (config bit `[1]`): selects whether the south
output comes from the output register (registered) or directly from the
raw result (combinational). The register itself only updates when the
enable bit is set.

The accumulator value is available as an operand in mode 2.

## Configuration

| Bit      | Field                                          |
|----------|------------------------------------------------|
| `[0]`    | Enable (gates accumulator and output register) |
| `[1]`    | Output register enable                         |
| `[3:2]`  | Operation mode                                 |
| `[15:4]` | Reserved                                       |

**Total: 16 bits**
