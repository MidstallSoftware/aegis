class YosysTclEmitter {
  final String moduleName;
  final int width;
  final int height;
  final int serdesCount;
  final int clockTileCount;

  const YosysTclEmitter({
    required this.moduleName,
    required this.width,
    required this.height,
    required this.serdesCount,
    required this.clockTileCount,
  });

  /// All modules that get pre-synthesized as hard macros.
  /// Includes tile types and helper modules with behavioral code.
  static const macroModules = [
    'Tile',
    'BramTile',
    'DspBasicTile',
    'ClockTile',
    'IOTile',
    'SerDesTile',
    'FabricConfigLoader',
  ];

  /// Backward compat alias
  static const tileModules = macroModules;

  /// Generates a per-module synthesis script.
  String generateTileSynth(String tileModule) {
    final buf = StringBuffer();

    buf.writeln('# Synthesize $tileModule as a hard macro');
    buf.writeln('# Auto-generated - run once per module type');
    buf.writeln();
    buf.writeln('yosys read_verilog -sv \$SV_FILE');
    buf.writeln('yosys hierarchy -top $tileModule');
    buf.writeln('yosys synth -top $tileModule -flatten');
    buf.writeln('yosys dfflibmap -liberty \$LIB_FILE');
    buf.writeln('yosys abc -liberty \$LIB_FILE');
    buf.writeln(
      'yosys hilomap -hicell \${CELL_LIB}__tieh Z '
      '-locell \${CELL_LIB}__tiel ZN',
    );
    buf.writeln('yosys opt_clean -purge');
    buf.writeln(
      'yosys write_verilog -noattr \${DEVICE_NAME}_${tileModule}_synth.v',
    );
    buf.writeln('yosys stat -liberty \$LIB_FILE');

    return buf.toString();
  }

  /// Generates the top-level assembly script.
  String generate() {
    final buf = StringBuffer();

    buf.writeln('# Auto-generated Yosys top-level assembly for $moduleName');
    buf.writeln(
      '# Fabric: ${width}x$height, $serdesCount SerDes, '
      '$clockTileCount clock tiles',
    );
    buf.writeln('#');
    buf.writeln('# All behavioral modules are pre-synthesized.');
    buf.writeln('# This script only assembles them - no synth/abc passes.');
    buf.writeln('#');
    buf.writeln('# TCL variables: SV_FILE, LIB_FILE, CELL_LIB, DEVICE_NAME,');
    buf.writeln('#                 STUBS_V');
    buf.writeln();

    // Read the full SV with behavioral module definitions
    buf.writeln('yosys read_verilog -sv \$SV_FILE');
    buf.writeln();

    buf.writeln('# Replace behavioral modules with blackbox stubs');
    for (final mod in macroModules) {
      buf.writeln('yosys delete $mod');
    }
    buf.writeln('yosys read_verilog -sv \$STUBS_V');
    buf.writeln();

    buf.writeln('yosys read_liberty -lib \$LIB_FILE');
    buf.writeln('yosys hierarchy -top $moduleName');
    buf.writeln();
    buf.writeln('# Lower remaining structural wrappers to gate-level');
    buf.writeln('# (instant - tiles are blackboxes, only glue logic remains)');
    buf.writeln('yosys proc');
    buf.writeln('yosys techmap');
    buf.writeln('yosys dfflibmap -liberty \$LIB_FILE');
    buf.writeln('yosys abc -liberty \$LIB_FILE');
    buf.writeln(
      'yosys hilomap -hicell \${CELL_LIB}__tieh Z '
      '-locell \${CELL_LIB}__tiel ZN',
    );
    buf.writeln('yosys opt_clean -purge');
    buf.writeln('yosys check');
    buf.writeln();

    buf.writeln('# Write final netlist');
    buf.writeln('yosys write_verilog -noattr -noexpr \${DEVICE_NAME}_synth.v');
    buf.writeln('yosys stat -liberty \$LIB_FILE');
    buf.writeln();

    return buf.toString();
  }
}
