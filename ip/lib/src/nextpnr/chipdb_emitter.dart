/// Emits a nextpnr-generic Python chipdb script for the Aegis FPGA.
///
/// The generated Python script defines BELs, wires, and pips that
/// describe the Aegis routing architecture to nextpnr-generic.
///
/// Tile input mux sources (3-bit sel):
///   0=north, 1=east, 2=south, 3=west, 4=clbOut, 5=const0, 6=const1
///
/// Output route mux sources (3-bit sel):
///   0=north, 1=east, 2=south, 3=west, 4=clbOut
class ChipdbEmitter {
  final String deviceName;
  final int width;
  final int height;
  final int tracks;
  final int serdesCount;
  final int clockTileCount;
  final int bramColumnInterval;
  final int bramDataWidth;
  final int bramAddrWidth;
  final int dspColumnInterval;

  /// Total I/O pads: 2*width + 2*height.
  int get totalPads => 2 * width + 2 * height;

  const ChipdbEmitter({
    required this.deviceName,
    required this.width,
    required this.height,
    required this.tracks,
    required this.serdesCount,
    required this.clockTileCount,
    this.bramColumnInterval = 0,
    this.bramDataWidth = 8,
    this.bramAddrWidth = 7,
    this.dspColumnInterval = 0,
  });

  /// Set of BRAM column indices.
  Set<int> get _bramColumns {
    if (bramColumnInterval <= 0) return {};
    final cols = <int>{};
    for (int x = bramColumnInterval; x < width; x += bramColumnInterval + 1) {
      cols.add(x);
    }
    return cols;
  }

  Set<int> get _dspColumns {
    if (dspColumnInterval <= 0) return {};
    final bram = _bramColumns;
    final cols = <int>{};
    for (int x = dspColumnInterval; x < width; x += dspColumnInterval + 1) {
      if (!bram.contains(x)) cols.add(x);
    }
    return cols;
  }

  /// Generates a pre-pack Python script that converts generic Yosys cells
  /// (`$lut`, `$_DFF_P_`) into Aegis cell types (`AEGIS_LUT4`, `AEGIS_DFF`)
  /// so they match the BEL types in the chipdb.
  String generatePacker() {
    final buf = StringBuffer();

    buf.writeln('# Auto-generated Aegis pre-pack script for $deviceName');
    buf.writeln(
      '# Converts generic Yosys cells to Aegis BEL-compatible types.',
    );
    buf.writeln();
    buf.writeln('for cname, cell in ctx.cells:');
    buf.writeln('    if cell.type == "\$lut":');
    buf.writeln('        cell.type = "AEGIS_LUT4"');
    buf.writeln('        # Rename ports: A[0]..A[3] -> in0..in3, Y -> out');
    buf.writeln('        cell.renamePort("A[0]", "in0")');
    buf.writeln('        cell.renamePort("A[1]", "in1")');
    buf.writeln('        cell.renamePort("A[2]", "in2")');
    buf.writeln('        cell.renamePort("A[3]", "in3")');
    buf.writeln('        cell.renamePort("Y", "out")');
    buf.writeln();
    buf.writeln('    elif cell.type == "\$_DFF_P_":');
    buf.writeln('        cell.type = "AEGIS_DFF"');
    buf.writeln('        cell.renamePort("C", "clk")');
    buf.writeln('        cell.renamePort("D", "d")');
    buf.writeln('        cell.renamePort("Q", "q")');
    buf.writeln();

    return buf.toString();
  }

  /// Generates the complete nextpnr-generic chipdb Python script.
  String generate() {
    final buf = StringBuffer();

    _writeHeader(buf);
    _writeHelpers(buf);
    _writeWires(buf);
    _writeBels(buf);
    _writePips(buf);
    _writeIoBels(buf);
    _writeConfig(buf);

    return buf.toString();
  }

  void _writeHeader(StringBuffer buf) {
    buf.writeln('# Auto-generated nextpnr-generic chipdb for $deviceName');
    buf.writeln('# Fabric: ${width}x$height, $tracks tracks per edge');
    buf.writeln('# SerDes: $serdesCount, Clock tiles: $clockTileCount');
    if (bramColumnInterval > 0) {
      buf.writeln(
        '# BRAM: every $bramColumnInterval columns, '
        '${bramDataWidth}x${1 << bramAddrWidth}',
      );
    }
    buf.writeln();
  }

  void _writeHelpers(StringBuffer buf) {
    buf.writeln('from itertools import product');
    buf.writeln();
    buf.writeln('W = $width   # fabric columns');
    buf.writeln('H = $height  # fabric rows');
    buf.writeln('T = $tracks  # routing tracks per edge');
    buf.writeln();
    buf.writeln('# Grid includes IO ring: logic at (1..W, 1..H),');
    buf.writeln('# IO pads at x=0,W+1,0,H+1');
    buf.writeln('GW = W + 2');
    buf.writeln('GH = H + 2');
    buf.writeln();
    buf.writeln('BRAM_COLS = ${_bramColumns.toList()..sort()}');
    buf.writeln('DSP_COLS = ${_dspColumns.toList()..sort()}');
    buf.writeln();
    buf.writeln('def wire_name(x, y, name):');
    buf.writeln('    return f"X{x}/Y{y}/{name}"');
    buf.writeln();
    buf.writeln('def bel_name(x, y, name):');
    buf.writeln('    return f"X{x}/Y{y}/{name}"');
    buf.writeln();
  }

  void _writeWires(StringBuffer buf) {
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln('# Wires');
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln();
    buf.writeln('for x, y in product(range(1, W + 1), range(1, H + 1)):');
    buf.writeln('    # CLB wires');
    buf.writeln('    for i in range(4):');
    buf.writeln(
      '        ctx.addWire(wire_name(x, y, f"CLB_I{i}"), '
      '"CLB_INPUT",x,y)',
    );
    buf.writeln(
      '    ctx.addWire(wire_name(x, y, "CLB_O"), '
      '"CLB_OUTPUT",x,y)',
    );
    buf.writeln(
      '    ctx.addWire(wire_name(x, y, "CLB_Q"), '
      '"CLB_FF_OUT",x,y)',
    );
    buf.writeln(
      '    ctx.addWire(wire_name(x, y, "CARRY_IN"), '
      '"CARRY",x,y)',
    );
    buf.writeln(
      '    ctx.addWire(wire_name(x, y, "CARRY_OUT"), '
      '"CARRY",x,y)',
    );
    buf.writeln();
    buf.writeln('    # Directional routing track wires');
    buf.writeln('    for d in ["N", "E", "S", "W"]:');
    buf.writeln('        for t in range(T):');
    buf.writeln(
      '            ctx.addWire('
      'wire_name(x, y, f"{d}{t}"), '
      '"ROUTING",x,y)',
    );
    buf.writeln();
    buf.writeln('    # Clock wire');
    buf.writeln(
      '    ctx.addWire(wire_name(x, y, "CLK"), '
      '"CLOCK",x,y)',
    );
    buf.writeln();

    // IO pad wires
    buf.writeln('# IO pad wires');
    buf.writeln('for i in range($totalPads):');
    buf.writeln('    ctx.addWire(f"IO{i}/PAD","IO_PAD",0,0)');
    buf.writeln('    ctx.addWire(f"IO{i}/I","IO_INPUT",0,0)');
    buf.writeln('    ctx.addWire(f"IO{i}/O","IO_OUTPUT",0,0)');
    buf.writeln('    ctx.addWire(f"IO{i}/OE","IO_OE",0,0)');
    buf.writeln();

    // Global clock wire
    buf.writeln('ctx.addWire("GLB_CLK","GLOBAL_CLOCK",0,0)');
    buf.writeln();
  }

  void _writeBels(StringBuffer buf) {
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln('# BELs');
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln();

    // LUT + DFF in each tile (skip BRAM and DSP columns)
    buf.writeln('for x, y in product(range(1, W + 1), range(1, H + 1)):');
    buf.writeln('    if x - 1 in BRAM_COLS or x - 1 in DSP_COLS:');
    buf.writeln('        continue');
    buf.writeln();
    buf.writeln('    # LUT4');
    buf.writeln('    lut_name = bel_name(x, y, "LUT4")');
    buf.writeln(
      '    ctx.addBel(lut_name, "AEGIS_LUT4", Loc(x, y, 0), False, False)',
    );
    buf.writeln(
      '    ctx.addBelInput(lut_name, "in0", wire_name(x, y, "CLB_I0"))',
    );
    buf.writeln(
      '    ctx.addBelInput(lut_name, "in1", wire_name(x, y, "CLB_I1"))',
    );
    buf.writeln(
      '    ctx.addBelInput(lut_name, "in2", wire_name(x, y, "CLB_I2"))',
    );
    buf.writeln(
      '    ctx.addBelInput(lut_name, "in3", wire_name(x, y, "CLB_I3"))',
    );
    buf.writeln(
      '    ctx.addBelOutput(lut_name, "out", wire_name(x, y, "CLB_O"))',
    );
    buf.writeln();

    // DFF
    buf.writeln('    # DFF');
    buf.writeln('    dff_name = bel_name(x, y, "DFF")');
    buf.writeln(
      '    ctx.addBel(dff_name, "AEGIS_DFF", Loc(x, y, 1), False, False)',
    );
    buf.writeln('    ctx.addBelInput(dff_name, "d", wire_name(x, y, "CLB_O"))');
    buf.writeln('    ctx.addBelInput(dff_name, "clk", wire_name(x, y, "CLK"))');
    buf.writeln(
      '    ctx.addBelOutput(dff_name, "q", wire_name(x, y, "CLB_Q"))',
    );
    buf.writeln();

    // Carry
    buf.writeln('    # Carry');
    buf.writeln('    carry_name = bel_name(x, y, "CARRY")');
    buf.writeln(
      '    ctx.addBel(carry_name, "AEGIS_CARRY", Loc(x, y, 2), False, False)',
    );
    buf.writeln(
      '    ctx.addBelInput(carry_name, "p", wire_name(x, y, "CLB_O"))',
    );
    buf.writeln(
      '    ctx.addBelInput(carry_name, "g", wire_name(x, y, "CLB_I0"))',
    );
    buf.writeln(
      '    ctx.addBelInput(carry_name, "ci", wire_name(x, y, "CARRY_IN"))',
    );
    buf.writeln(
      '    ctx.addBelOutput(carry_name, "co", wire_name(x, y, "CARRY_OUT"))',
    );
    buf.writeln();

    // BRAM BELs
    if (bramColumnInterval > 0) {
      buf.writeln('# BRAM BELs');
      buf.writeln('for x, y in product(range(1, W + 1), range(1, H + 1)):');
      buf.writeln('    if x - 1 not in BRAM_COLS:');
      buf.writeln('        continue');
      buf.writeln();
      buf.writeln('    bn = bel_name(x, y, "BRAM")');
      buf.writeln(
        '    ctx.addBel(bn, "AEGIS_BRAM", Loc(x, y, 0), False, False)',
      );
      buf.writeln('    ctx.addBelInput(bn, "clk", wire_name(x, y, "CLK"))');
      // Clamp BRAM pins to available tracks
      final effAddr = bramAddrWidth < tracks ? bramAddrWidth : tracks - 1;
      final effData = (bramAddrWidth + bramDataWidth) < tracks
          ? bramDataWidth
          : tracks - effAddr - 1;
      final hasWe = (effAddr + effData) < tracks;
      for (final port in ['a', 'b']) {
        final dir = port == 'a' ? 'N' : 'W';
        final outDir = port == 'a' ? 'S' : 'E';
        for (int i = 0; i < effAddr; i++) {
          buf.writeln(
            '    ctx.addBelInput(bn, "${port}_addr[$i]", wire_name(x, y, "$dir$i"))',
          );
        }
        for (int i = 0; i < effData; i++) {
          final trackIdx = effAddr + i;
          buf.writeln(
            '    ctx.addBelInput(bn, "${port}_wdata[$i]", wire_name(x, y, "$dir$trackIdx"))',
          );
        }
        if (hasWe) {
          buf.writeln(
            '    ctx.addBelInput(bn, "${port}_we", wire_name(x, y, "$dir${effAddr + effData}"))',
          );
        }
        for (int i = 0; i < effData && i < tracks; i++) {
          buf.writeln(
            '    ctx.addBelOutput(bn, "${port}_rdata[$i]", wire_name(x, y, "$outDir$i"))',
          );
        }
      }
      buf.writeln();
    }

    // DSP BELs
    if (dspColumnInterval > 0) {
      buf.writeln('# DSP BELs');
      buf.writeln('for x, y in product(range(1, W + 1), range(1, H + 1)):');
      buf.writeln('    if x - 1 not in DSP_COLS:');
      buf.writeln('        continue');
      buf.writeln();
      buf.writeln('    dn = bel_name(x, y, "DSP")');
      buf.writeln(
        '    ctx.addBel(dn, "AEGIS_DSP", Loc(x, y, 0), False, False)',
      );
      buf.writeln('    ctx.addBelInput(dn, "clk", wire_name(x, y, "CLK"))');
      for (int i = 0; i < 18 && i < tracks; i++) {
        buf.writeln('    ctx.addBelInput(dn, "a[$i]", wire_name(x, y, "N$i"))');
      }
      for (int i = 0; i < 18 && i < tracks; i++) {
        buf.writeln('    ctx.addBelInput(dn, "b[$i]", wire_name(x, y, "W$i"))');
      }
      for (int i = 0; i < 36 && i < tracks; i++) {
        buf.writeln(
          '    ctx.addBelOutput(dn, "result[$i]", wire_name(x, y, "S$i"))',
        );
      }
      buf.writeln();
    }
  }

  void _writePips(StringBuffer buf) {
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln('# Pips');
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln();

    // CLB input mux pips: routing tracks → CLB inputs
    buf.writeln('PIP_DELAY = 0.1');
    buf.writeln();
    buf.writeln('for x, y in product(range(1, W + 1), range(1, H + 1)):');
    buf.writeln('    if x - 1 in BRAM_COLS or x - 1 in DSP_COLS:');
    buf.writeln('        continue');
    buf.writeln();
    buf.writeln(
      '    # CLB input mux: each input can come from '
      'N0/E0/S0/W0/feedback/const',
    );
    buf.writeln('    for i in range(4):');
    buf.writeln('        clb_in = wire_name(x, y, f"CLB_I{i}")');
    buf.writeln('        # From each directional track 0');
    buf.writeln(
      '        for d, idx in [("N", 0), ("E", 1), '
      '("S", 2), ("W", 3)]:',
    );
    buf.writeln('            src = wire_name(x, y, f"{d}0")');
    buf.writeln(
      '            ctx.addPip(f"X{x}/Y{y}/MUX_I{i}_{d}", '
      '"CLB_MUX",src,clb_in, '
      'ctx.getDelayFromNS(PIP_DELAY), Loc(x, y, 0))',
    );
    buf.writeln('        # Feedback from CLB output');
    buf.writeln(
      '        ctx.addPip(f"X{x}/Y{y}/MUX_I{i}_FB", '
      '"CLB_MUX",wire_name(x, y, "CLB_O"), '
      'clb_in, '
      'ctx.getDelayFromNS(PIP_DELAY), Loc(x, y, 0))',
    );
    buf.writeln('        # Feedback from DFF output');
    buf.writeln(
      '        ctx.addPip(f"X{x}/Y{y}/MUX_I{i}_Q", '
      '"CLB_MUX",wire_name(x, y, "CLB_Q"), '
      'clb_in, '
      'ctx.getDelayFromNS(PIP_DELAY), Loc(x, y, 0))',
    );
    buf.writeln();

    // Output route pips: CLB output / routing → directional output tracks
    buf.writeln(
      '    # Output route mux: each direction can source from '
      'N/E/S/W tracks or CLB output',
    );
    buf.writeln('    for d_out in ["N", "E", "S", "W"]:');
    buf.writeln('        for t in range(T):');
    buf.writeln('            dst = wire_name(x, y, f"{d_out}{t}")');
    buf.writeln('            # From CLB output');
    buf.writeln(
      '            ctx.addPip('
      'f"X{x}/Y{y}/RT_{d_out}{t}_CLB", '
      '"ROUTE_MUX",wire_name(x, y, "CLB_O"), '
      'dst, '
      'ctx.getDelayFromNS(PIP_DELAY), Loc(x, y, 0))',
    );
    buf.writeln('            # From DFF output');
    buf.writeln(
      '            ctx.addPip('
      'f"X{x}/Y{y}/RT_{d_out}{t}_Q", '
      '"ROUTE_MUX",wire_name(x, y, "CLB_Q"), '
      'dst, '
      'ctx.getDelayFromNS(PIP_DELAY), Loc(x, y, 0))',
    );
    buf.writeln();

    // Inter-tile routing pips
    buf.writeln(
      '    # Inter-tile routing: connect output tracks to '
      'neighboring tile input tracks',
    );
    buf.writeln('    for t in range(T):');
    buf.writeln('        # North output → neighbor north input');
    buf.writeln('        if y > 1:');
    buf.writeln(
      '            ctx.addPip('
      'f"X{x}/Y{y}/NORTH{t}_UP","INTER_TILE", '
      'wire_name(x, y, f"N{t}"), '
      'wire_name(x, y - 1, f"S{t}"), '
      'ctx.getDelayFromNS(PIP_DELAY * 2), Loc(x, y, 0))',
    );
    buf.writeln('        # South output → neighbor south input');
    buf.writeln('        if y < H:');
    buf.writeln(
      '            ctx.addPip('
      'f"X{x}/Y{y}/SOUTH{t}_DOWN","INTER_TILE", '
      'wire_name(x, y, f"S{t}"), '
      'wire_name(x, y + 1, f"N{t}"), '
      'ctx.getDelayFromNS(PIP_DELAY * 2), Loc(x, y, 0))',
    );
    buf.writeln('        # East output → neighbor east input');
    buf.writeln('        if x < W:');
    buf.writeln(
      '            ctx.addPip('
      'f"X{x}/Y{y}/EAST{t}_RIGHT","INTER_TILE", '
      'wire_name(x, y, f"E{t}"), '
      'wire_name(x + 1, y, f"W{t}"), '
      'ctx.getDelayFromNS(PIP_DELAY * 2), Loc(x, y, 0))',
    );
    buf.writeln('        # West output → neighbor west input');
    buf.writeln('        if x > 1:');
    buf.writeln(
      '            ctx.addPip('
      'f"X{x}/Y{y}/WEST{t}_LEFT","INTER_TILE", '
      'wire_name(x, y, f"W{t}"), '
      'wire_name(x - 1, y, f"E{t}"), '
      'ctx.getDelayFromNS(PIP_DELAY * 2), Loc(x, y, 0))',
    );
    buf.writeln();

    // Carry chain pips (south to north within column)
    buf.writeln('    # Carry chain: south → north');
    buf.writeln('    if y < H:');
    buf.writeln(
      '        ctx.addPip('
      'f"X{x}/Y{y}/CARRY_UP","CARRY", '
      'wire_name(x, y, "CARRY_OUT"), '
      'wire_name(x, y + 1, "CARRY_IN"), '
      'ctx.getDelayFromNS(PIP_DELAY * 0.5), Loc(x, y, 0))',
    );
    buf.writeln();

    // Global clock distribution
    buf.writeln('    # Clock distribution');
    buf.writeln(
      '    ctx.addPip('
      'f"X{x}/Y{y}/GLB_CLK","CLOCK", '
      '"GLB_CLK", wire_name(x, y, "CLK"), '
      'ctx.getDelayFromNS(PIP_DELAY), Loc(x, y, 0))',
    );
    buf.writeln();
  }

  void _writeIoBels(StringBuffer buf) {
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln('# I/O BELs');
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln();
    buf.writeln('for i in range($totalPads):');
    buf.writeln('    iob_name = f"IO{i}"');
    buf.writeln(
      '    ctx.addBel(iob_name, "GENERIC_IOB", Loc(0, i, 0), False, False)',
    );
    buf.writeln('    ctx.addBelInout(iob_name, "PAD", f"IO{i}/PAD")');
    buf.writeln('    ctx.addBelInput(iob_name, "I", f"IO{i}/I")');
    buf.writeln('    ctx.addBelOutput(iob_name, "O", f"IO{i}/O")');
    buf.writeln('    ctx.addBelInput(iob_name, "EN", f"IO{i}/OE")');
    buf.writeln();

    // Connect IO pads to edge tiles
    buf.writeln('# Connect IO pads to edge fabric tiles');
    buf.writeln('pad_idx = 0');
    buf.writeln();

    // North edge
    buf.writeln('# North edge');
    buf.writeln('for x in range(1, W + 1):');
    buf.writeln('    for t in range(T):');
    buf.writeln(
      '        ctx.addPip(f"IO{pad_idx}/TO_N{t}", '
      '"IO_ROUTE", '
      'f"IO{pad_idx}/O", '
      'wire_name(x, 1, f"N{t}"), '
      'ctx.getDelayFromNS(PIP_DELAY), Loc(0, pad_idx, 0))',
    );
    buf.writeln(
      '        ctx.addPip(f"IO{pad_idx}/FROM_S{t}", '
      '"IO_ROUTE", '
      'wire_name(x, 1, f"S{t}"), '
      'f"IO{pad_idx}/I", '
      'ctx.getDelayFromNS(PIP_DELAY), Loc(0, pad_idx, 0))',
    );
    buf.writeln('    pad_idx += 1');
    buf.writeln();

    // East edge
    buf.writeln('# East edge');
    buf.writeln('for y in range(1, H + 1):');
    buf.writeln('    for t in range(T):');
    buf.writeln(
      '        ctx.addPip(f"IO{pad_idx}/TO_E{t}", '
      '"IO_ROUTE", '
      'f"IO{pad_idx}/O", '
      'wire_name(W, y, f"E{t}"), '
      'ctx.getDelayFromNS(PIP_DELAY), Loc(0, pad_idx, 0))',
    );
    buf.writeln(
      '        ctx.addPip(f"IO{pad_idx}/FROM_W{t}", '
      '"IO_ROUTE", '
      'wire_name(W, y, f"W{t}"), '
      'f"IO{pad_idx}/I", '
      'ctx.getDelayFromNS(PIP_DELAY), Loc(0, pad_idx, 0))',
    );
    buf.writeln('    pad_idx += 1');
    buf.writeln();

    // South edge
    buf.writeln('# South edge');
    buf.writeln('for x in range(1, W + 1):');
    buf.writeln('    for t in range(T):');
    buf.writeln(
      '        ctx.addPip(f"IO{pad_idx}/TO_S{t}", '
      '"IO_ROUTE", '
      'f"IO{pad_idx}/O", '
      'wire_name(x, H, f"S{t}"), '
      'ctx.getDelayFromNS(PIP_DELAY), Loc(0, pad_idx, 0))',
    );
    buf.writeln(
      '        ctx.addPip(f"IO{pad_idx}/FROM_N{t}", '
      '"IO_ROUTE", '
      'wire_name(x, H, f"N{t}"), '
      'f"IO{pad_idx}/I", '
      'ctx.getDelayFromNS(PIP_DELAY), Loc(0, pad_idx, 0))',
    );
    buf.writeln('    pad_idx += 1');
    buf.writeln();

    // West edge
    buf.writeln('# West edge');
    buf.writeln('for y in range(1, H + 1):');
    buf.writeln('    for t in range(T):');
    buf.writeln(
      '        ctx.addPip(f"IO{pad_idx}/TO_W{t}", '
      '"IO_ROUTE", '
      'f"IO{pad_idx}/O", '
      'wire_name(1, y, f"W{t}"), '
      'ctx.getDelayFromNS(PIP_DELAY), Loc(0, pad_idx, 0))',
    );
    buf.writeln(
      '        ctx.addPip(f"IO{pad_idx}/FROM_E{t}", '
      '"IO_ROUTE", '
      'wire_name(1, y, f"E{t}"), '
      'f"IO{pad_idx}/I", '
      'ctx.getDelayFromNS(PIP_DELAY), Loc(0, pad_idx, 0))',
    );
    buf.writeln('    pad_idx += 1');
    buf.writeln();
  }

  void _writeConfig(StringBuffer buf) {
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln('# Configuration');
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln();
    buf.writeln('ctx.setLutK(4)');
    buf.writeln('ctx.setDelayScaling(1.0, 0.0)');
    buf.writeln();

    // Timing
    buf.writeln('# Cell timing');
    buf.writeln('ctx.addCellTimingClock("AEGIS_DFF", "clk")');
    buf.writeln(
      'ctx.addCellTimingSetupHold("AEGIS_DFF", '
      '"d", "clk", ctx.getDelayFromNS(0.2), ctx.getDelayFromNS(0.1))',
    );
    buf.writeln(
      'ctx.addCellTimingClockToOut("AEGIS_DFF", '
      '"q", "clk", ctx.getDelayFromNS(0.5))',
    );
    buf.writeln();
    for (final pin in ['in0', 'in1', 'in2', 'in3']) {
      buf.writeln(
        'ctx.addCellTimingDelay("AEGIS_LUT4", '
        '"$pin", "out", ctx.getDelayFromNS(0.3))',
      );
    }
    buf.writeln();
    buf.writeln(
      'ctx.addCellTimingDelay("AEGIS_CARRY", '
      '"ci", "co", ctx.getDelayFromNS(0.05))',
    );
    buf.writeln(
      'ctx.addCellTimingDelay("AEGIS_CARRY", '
      '"p", "co", ctx.getDelayFromNS(0.15))',
    );
    buf.writeln();
  }
}
