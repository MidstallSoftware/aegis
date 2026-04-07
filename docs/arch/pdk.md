# PDK Integration and Tapeout

Aegis uses a pluggable PDK (Process Design Kit) abstraction to support
multiple foundry targets. The digital FPGA fabric is described in
ROHD/Dart and synthesized to standard cells from the chosen PDK. Analog
peripherals (PLL, SerDes, I/O cells) are replaced with PDK-provided
symbols during tapeout.

## Supported PDKs

| PDK      | Foundry         | Node  | Standard Cell Library     | Site Name           |
|----------|-----------------|-------|---------------------------|---------------------|
| GF180MCU | GlobalFoundries | 180nm | `gf180mcu_fd_sc_mcu7t5v0` | `GF018hv5v_mcu_sc7` |
| Sky130   | SkyWater        | 130nm | `sky130_fd_sc_hd`         | `unithd`            |

Both PDK packages are built as Nix derivations and expose a consistent
interface: standard cell liberty files, LEF files, GDS cell libraries,
and spice models.

## PDK Provider Interface

The `PdkProvider` abstract class defines how Aegis maps its canonical
block interfaces to PDK-specific symbols and pin names. Each provider
implements three methods:

- `pll()`: returns symbol path and pin mapping for the clock PLL
- `serdes()`: returns symbol path and pin mapping for the serial transceiver
- `ioCell()`: returns symbol path and pin mapping for the I/O pad cell

A provider registry allows selection by name (`generic`, `gf180mcu`).
The `generic` provider uses bundled Aegis symbols with identity pin
mapping for simulation and development.

### Pin Mapping Example (GF180MCU)

The GF180MCU provider translates Aegis pin names to foundry-specific
names:

| Block   | Aegis Pin         | GF180MCU Pin |
|---------|-------------------|--------------|
| PLL     | `refClk`          | `CLK`        |
| PLL     | `reset`           | `RST`        |
| PLL     | `clkOut[0]`       | `CLKOUT0`    |
| PLL     | `locked`          | `LOCK`       |
| SerDes  | `serialIn`        | `RXD`        |
| SerDes  | `serialOut`       | `TXD`        |
| SerDes  | `txReady`         | `TX_RDY`     |
| SerDes  | `rxValid`         | `RX_VLD`     |
| I/O     | `padIn`           | `PAD`        |
| I/O     | `padOut`          | `A`          |
| I/O     | `padOutputEnable` | `EN`         |

## Analog Block Wrappers

The digital tile implementations (ClockTile, SerDesTile, IOTile) are
used for simulation and bitstream tooling. For tapeout, they are replaced
by analog wrappers that instantiate the PDK-provided symbols:

- **AnalogPll**: replaces ClockTile with a PDK PLL macro
- **AnalogSerdes**: replaces SerDesTile with a PDK transceiver macro
- **AnalogIoCell**: replaces IOTile with a PDK I/O pad cell

Each wrapper queries the active `PdkProvider` for the symbol path and
pin mapping, then generates xschem schematic output (`.sch` format) with
the correct PDK instances and wiring.

## Xschem Generation

The IP generator produces two forms of xschem output for the
mixed-signal top level:

- **TCL script** (`<device>-xschem.tcl`): for programmatic schematic
  construction via `xschem --tcl`
- **Schematic file** (`<device>-xschem.sch`): static xschem schematic
  that can be opened directly

Both place the digital FPGA module at the center with analog blocks
arranged around it: PLLs to the left, SerDes to the right, and I/O cells
around the perimeter matching the fabric edge mapping.

## Tapeout Pipeline

The tapeout flow is a five-stage RTL-to-GDS pipeline, driven entirely
through Nix:

```
nix build .#terra-1-tapeout
```

### Stage 1: Synthesis (Yosys)

Reads the generated SystemVerilog and maps it to PDK standard cells
using the liberty timing library. Outputs a gate-level netlist.

### Stage 2: Constraints (SDC)

Generates timing constraints with a configurable clock period (e.g.,
`clockPeriodNs = 20` for 50 MHz).

### Stage 3: Place and Route (OpenROAD)

Performs floorplanning, power grid generation, cell placement, clock
tree synthesis, and detailed routing using PDK tech LEF and cell LEFs.
Outputs a placed-and-routed DEF and timing/power reports.

### Stage 4: GDS Merge (KLayout)

Reads the routed DEF and merges it with the PDK cell GDS library to
produce the final GDS2 file for fab submission.

### Stage 5: Layout Visualization (KLayout)

Renders the GDS to a PNG image for visual inspection.

### Output Artifacts

```
result/
  terra_1_synth.v       # Gate-level netlist
  terra_1_final.def     # Placed and routed layout
  terra_1.gds           # GDS2 for fab submission
  terra_1_layout.png    # Layout render
  timing.rpt            # Timing analysis
  power.rpt             # Power report
```

## Adding a New PDK

To add support for a new foundry PDK:

1. Create a Nix package under `pkgs/` that builds the PDK's standard
   cell library, LEFs, GDS, and liberty files.
2. Implement a `PdkProvider` subclass that maps Aegis pin names to the
   new PDK's symbol pins.
3. Register the provider in `PdkProvider.registry`.
4. The tapeout pipeline will work unchanged, since it reads PDK paths
   and cell library names from the Nix package's passthru attributes.
