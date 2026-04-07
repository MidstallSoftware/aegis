# Block RAM (BRAM) Tile

BRAM tiles provide on-chip memory distributed across the fabric in
dedicated columns. Each BRAM tile implements a dual-port synchronous RAM
that can be read and written independently from two directions.

## Parameters

| Parameter    | Default | Description                   |
|--------------|---------|-------------------------------|
| Data width   | 8 bits  | Width of each memory word     |
| Address width| 7 bits  | Address bus width             |
| Depth        | 128     | Number of words (2^addrWidth) |

## Ports

The two ports are mapped to the tile's directional routing:

- **Port A**: input from the north, output to the south
- **Port B**: input from the west, output to the east

Data, address, and write-enable signals are packed into the routing
tracks. The packing adapts to the available track width:

```
[effAddrWidth-1 : 0]                         Address bits
[effAddrWidth+effDataWidth-1 : effAddrWidth] Data bits
[effAddrWidth+effDataWidth]                  Write-enable (if tracks allow)
```

If the track width is narrower than the full address + data width, the
signals are truncated and zero-extended.

## Read/Write Behavior

**Writes** are synchronous. On the rising clock edge, if the port is
enabled and write-enable is asserted, the data word is stored at the
given address. Both ports can write simultaneously (true dual-port).

**Reads** are asynchronous (combinational). When a port is enabled, the
data at the addressed location is continuously driven onto the output
tracks. When disabled, the output is zero.

## Carry Chain

BRAM tiles pass the carry signal through unchanged (`carryOut = carryIn`).
They do not consume or generate carry values.

## Configuration

| Bit    | Field         |
|--------|---------------|
| `[0]`  | Port A enable |
| `[1]`  | Port B enable |
| `[7:2]`| Reserved      |

**Total: 8 bits**
