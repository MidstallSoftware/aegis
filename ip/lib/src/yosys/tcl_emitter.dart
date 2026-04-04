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

  /// Generates the complete Yosys TCL synthesis script.
  String generate() {
    final buf = StringBuffer();

    _writeHeader(buf);
    _writeRead(buf);
    _writeSynth(buf);
    _writeMapping(buf);
    _writeOutput(buf);

    return buf.toString();
  }

  void _writeHeader(StringBuffer buf) {
    buf.writeln('# Auto-generated Yosys synthesis script for $moduleName');
    buf.writeln(
      '# Fabric: ${width}x$height, $serdesCount SerDes, '
      '$clockTileCount clock tiles',
    );
    buf.writeln('#');
    buf.writeln('# TCL variables (SV_FILE, LIB_FILE, CELL_LIB, DEVICE_NAME)');
    buf.writeln('# must be set before sourcing this script.');
    buf.writeln();
  }

  void _writeRead(StringBuffer buf) {
    buf.writeln('# Read design');
    buf.writeln('yosys read_verilog -sv \$SV_FILE');
    buf.writeln();
  }

  void _writeSynth(StringBuffer buf) {
    buf.writeln('# Hierarchical synthesis (no -flatten)');
    buf.writeln('#');
    buf.writeln('# Each unique tile module (Tile, BramTile, etc.) is');
    buf.writeln('# synthesized once and reused across all instances.');
    buf.writeln('# Flattening a ${width}x$height fabric would require');
    buf.writeln('# hundreds of GB of RAM.');
    buf.writeln('yosys synth -top $moduleName');
    buf.writeln();
  }

  void _writeMapping(StringBuffer buf) {
    buf.writeln('# Map flip-flops to PDK cells');
    buf.writeln('yosys dfflibmap -liberty \$LIB_FILE');
    buf.writeln();
    buf.writeln('# Map combinational logic to PDK cells');
    buf.writeln('yosys abc -liberty \$LIB_FILE');
    buf.writeln();
    buf.writeln('# Map tie-high/tie-low to PDK cells');
    buf.writeln(
      'yosys hilomap -hicell \${CELL_LIB}__tieh Z '
      '-locell \${CELL_LIB}__tiel ZN',
    );
    buf.writeln();
    buf.writeln('# Clean up');
    buf.writeln('yosys opt_clean -purge');
    buf.writeln();
  }

  void _writeOutput(StringBuffer buf) {
    buf.writeln('# Write outputs');
    buf.writeln('yosys write_verilog -noattr \${DEVICE_NAME}_synth.v');
    buf.writeln('yosys stat -liberty \$LIB_FILE');
    buf.writeln();
  }
}
