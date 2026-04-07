# SerDes Tile

SerDes tiles provide protocol-agnostic serial transceivers on the fabric
perimeter. Each tile has a transmit (TX) and receive (RX) path with
configurable word length, bit order, clock rate, and sampling mode. The
design is intentionally generic: protocols like UART, SPI, or custom
serial links are defined entirely by configuration.

## External Pins

- `serialIn`: 1-bit input (RX data from off-chip)
- `serialOut`: 1-bit output (TX data to off-chip)

## TX Path

The transmitter loads a data word from the fabric and shifts it out one
bit at a time at the configured baud rate.

1. Data is loaded from a configurable fabric track into a 256-bit shift
   register when a strobe signal is asserted.
2. On each baud tick, the register shifts and the next bit appears on
   `serialOut`.
3. Bit order is selectable: MSB-first shifts from the top of the
   register, LSB-first shifts from the bottom.
4. When idle, the output level is configurable (high or low).
5. `txReady` signals that the transmitter can accept a new word.

## RX Path

The receiver samples `serialIn` at the baud rate and assembles incoming
bits into a word.

1. Each baud tick, the sampled bit is shifted into a 256-bit receive
   register.
2. A counter tracks how many bits have been received. When it reaches the
   configured word length, `rxValid` pulses to indicate a complete frame.
3. The received data is driven onto a configurable fabric track, with the
   valid bit on the adjacent track.

## Baud Rate Generator

An 8-bit clock divider generates the baud tick by dividing the fabric
clock by `(clockDivider + 1)`, giving a range of 1x to 256x division.

In **DDR mode**, the baud tick fires both at the counter rollover and at
the halfway point, doubling the effective sample rate.

**Clock polarity** inverts the sample timing when set.

## Loopback

A loopback mode connects the TX output back to the RX input for
self-testing without external connections.

## Configuration

| Bits       | Field                                    |
|------------|------------------------------------------|
| `[0]`      | TX enable                                |
| `[1]`      | RX enable                                |
| `[4:2]`    | TX data track select                     |
| `[7:5]`    | RX data track select                     |
| `[15:8]`   | Word length - 1 (range 1 to 256)         |
| `[16]`     | Bit order (0 = LSB-first, 1 = MSB-first) |
| `[17]`     | TX idle level (0 = low, 1 = high)        |
| `[18]`     | Clock mode (0 = SDR, 1 = DDR)            |
| `[19]`     | Clock polarity (0 = rising, 1 = falling) |
| `[27:20]`  | Clock divider - 1                        |
| `[28]`     | Loopback enable                          |
| `[30:29]`  | TX strobe track select                   |
| `[31]`     | Reserved                                 |

**Total: 32 bits**
