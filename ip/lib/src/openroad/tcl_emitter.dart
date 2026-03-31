/// Emits an OpenROAD TCL script for place-and-route.
class OpenroadTclEmitter {
  final String moduleName;
  final int width;
  final int height;
  final int serdesCount;
  final int clockTileCount;
  final bool hasConfigClk;

  /// Total I/O pads: 2*width + 2*height.
  int get totalPads => 2 * width + 2 * height;

  const OpenroadTclEmitter({
    required this.moduleName,
    required this.width,
    required this.height,
    required this.serdesCount,
    required this.clockTileCount,
    this.hasConfigClk = false,
  });

  /// Generates the complete OpenROAD TCL script.
  String generate() {
    final buf = StringBuffer();

    _writeHeader(buf);
    _writeReadInputs(buf);
    _writeFloorplan(buf);
    _writePinPlacement(buf);
    _writePowerGrid(buf);
    _writePlacement(buf);
    _writeCts(buf);
    _writeRouting(buf);
    _writeReports(buf);
    _writeOutputs(buf);

    return buf.toString();
  }

  void _writeHeader(StringBuffer buf) {
    buf.writeln('# Auto-generated OpenROAD TCL script for $moduleName');
    buf.writeln(
      '# Fabric: ${width}x$height, $serdesCount SerDes, '
      '$clockTileCount clock tiles',
    );
    buf.writeln('#');
    buf.writeln('# Shell variables are substituted at build time.');
    buf.writeln();
  }

  void _writeReadInputs(StringBuffer buf) {
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln('# Read inputs');
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln();
    buf.writeln('read_liberty \$LIB_FILE');
    buf.writeln('read_lef \$TECH_LEF');
    buf.writeln();
    buf.writeln('# Read cell LEFs');
    buf.writeln('foreach lef [glob -directory \$CELL_LEF_DIR *.lef] {');
    buf.writeln('    if {![string match "*tech*" \$lef]} {');
    buf.writeln('        read_lef \$lef');
    buf.writeln('    }');
    buf.writeln('}');
    buf.writeln();
    buf.writeln('read_verilog \$SYNTH_V');
    buf.writeln('link_design $moduleName');
    buf.writeln('read_sdc \$SDC_FILE');
    buf.writeln();
  }

  void _writeFloorplan(StringBuffer buf) {
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln('# Floorplan');
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln();
    buf.writeln('if {[info exists DIE_AREA]} {');
    buf.writeln('    initialize_floorplan \\');
    buf.writeln('        -die_area \$DIE_AREA \\');
    buf.writeln('        -core_space 2 \\');
    buf.writeln('        -site \$SITE_NAME');
    buf.writeln('} else {');
    buf.writeln('    initialize_floorplan \\');
    buf.writeln('        -utilization \$UTILIZATION \\');
    buf.writeln('        -core_space 2 \\');
    buf.writeln('        -site \$SITE_NAME');
    buf.writeln('}');
    buf.writeln();

    // Generate routing tracks - pitches are read from tech LEF layer defs
    buf.writeln('# Generate routing tracks');
    buf.writeln('# Pitches should match the tech LEF layer definitions');
    buf.writeln('foreach layer {Metal1 Metal2 Metal3 Metal4 Metal5 Metal6} {');
    buf.writeln(
      '    if {![catch {set tech_layer '
      '[[[ord::get_db] getTech] findLayer \$layer]}]} {',
    );
    buf.writeln('        if {\$tech_layer ne "NULL"} {');
    buf.writeln(
      '            set pitch_x '
      '[ord::dbu_to_microns [\$tech_layer getPitchX]]',
    );
    buf.writeln(
      '            set pitch_y '
      '[ord::dbu_to_microns [\$tech_layer getPitchY]]',
    );
    buf.writeln('            if {\$pitch_x > 0 && \$pitch_y > 0} {');
    buf.writeln('                make_tracks \$layer \\');
    buf.writeln('                    -x_offset 0 -x_pitch \$pitch_x \\');
    buf.writeln('                    -y_offset 0 -y_pitch \$pitch_y');
    buf.writeln('            }');
    buf.writeln('        }');
    buf.writeln('    }');
    buf.writeln('}');
    buf.writeln();
  }

  void _writePinPlacement(StringBuffer buf) {
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln('# Pin placement');
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln();

    // Group pins by function and edge:
    // - North: pad I/O for the north edge of the FPGA fabric
    // - South: pad I/O for the south edge
    // - East: SerDes pins
    // - West: clock, reset, config

    // Clock and control pins on west edge
    final westPins = <String>['clk', 'reset', 'configDone'];
    if (hasConfigClk) westPins.add('configClk');
    // Config read port
    westPins.addAll([
      'configRead_en',
      'configRead_addr\\[*\\]',
      'configRead_data\\[*\\]',
    ]);

    // SerDes pins on east edge
    final eastPins = <String>[];
    if (serdesCount > 0) {
      eastPins.addAll([
        'serialIn\\[*\\]',
        'serialOut\\[*\\]',
        'txReady\\[*\\]',
        'rxValid\\[*\\]',
      ]);
    }

    // Clock outputs on east edge too
    if (clockTileCount > 0) {
      eastPins.addAll(['clkOut\\[*\\]', 'clkLocked\\[*\\]']);
    }

    // Pad I/O split between north and south
    final northSouthPins = [
      'padIn\\[*\\]',
      'padOut\\[*\\]',
      'padOutputEnable\\[*\\]',
    ];

    buf.writeln('# West edge: clock, reset, config');
    buf.writeln('set west_pins [list \\');
    for (final pin in westPins) {
      buf.writeln('    $pin \\');
    }
    buf.writeln(']');
    buf.writeln();

    buf.writeln('# East edge: SerDes, clock outputs');
    buf.writeln('set east_pins [list \\');
    for (final pin in eastPins) {
      buf.writeln('    $pin \\');
    }
    buf.writeln(']');
    buf.writeln();

    buf.writeln('# North/South edges: pad I/O');
    buf.writeln('set ns_pins [list \\');
    for (final pin in northSouthPins) {
      buf.writeln('    $pin \\');
    }
    buf.writeln(']');
    buf.writeln();

    // Use place_pins with pin groups for edge assignment
    // Find available routing layers
    buf.writeln('# Find routing layers for pin placement');
    buf.writeln('set hor_layer ""');
    buf.writeln('set ver_layer ""');
    buf.writeln('foreach layer {Metal2 Metal3 Metal4} {');
    buf.writeln(
      '    if {![catch {set tl '
      '[[[ord::get_db] getTech] findLayer \$layer]}]} {',
    );
    buf.writeln('        if {\$tl ne "NULL"} {');
    buf.writeln('            set dir [\$tl getDirection]');
    buf.writeln(
      '            if {\$dir eq "HORIZONTAL" && \$hor_layer eq ""} {',
    );
    buf.writeln('                set hor_layer \$layer');
    buf.writeln('            }');
    buf.writeln('            if {\$dir eq "VERTICAL" && \$ver_layer eq ""} {');
    buf.writeln('                set ver_layer \$layer');
    buf.writeln('            }');
    buf.writeln('        }');
    buf.writeln('    }');
    buf.writeln('}');
    buf.writeln();
    buf.writeln('if {\$hor_layer eq ""} { set hor_layer Metal1 }');
    buf.writeln('if {\$ver_layer eq ""} { set ver_layer Metal2 }');
    buf.writeln();
    buf.writeln('place_pins -hor_layers \$hor_layer -ver_layers \$ver_layer');
    buf.writeln();
  }

  void _writePowerGrid(StringBuffer buf) {
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln('# Power/ground connections');
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln();
    buf.writeln('add_global_connection -net VDD -pin_pattern VDD -power');
    buf.writeln('add_global_connection -net VSS -pin_pattern VSS -ground');
    buf.writeln('global_connect');
    buf.writeln();
  }

  void _writePlacement(StringBuffer buf) {
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln('# Placement');
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln();
    buf.writeln('global_placement -density \$UTILIZATION');
    buf.writeln('detailed_placement');
    buf.writeln();
  }

  void _writeCts(StringBuffer buf) {
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln('# Clock tree synthesis');
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln();
    buf.writeln('estimate_parasitics -placement');
    buf.writeln();
    buf.writeln('# Use larger clock buffers for routable CTS');
    buf.writeln('set cts_bufs {}');
    buf.writeln('foreach sz {2 4 8 16} {');
    buf.writeln('    set cell_name \${CELL_LIB}__clkbuf_\$sz');
    buf.writeln('    lappend cts_bufs \$cell_name');
    buf.writeln('}');
    buf.writeln('clock_tree_synthesis -buf_list \$cts_bufs');
    buf.writeln();
    buf.writeln('# Post-CTS legalization');
    buf.writeln('detailed_placement');
    buf.writeln();
  }

  void _writeRouting(StringBuffer buf) {
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln('# Routing');
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln();
    buf.writeln('set_routing_layers -signal Metal1-Metal4');
    buf.writeln('global_route -allow_congestion');
    buf.writeln('detailed_route');
    buf.writeln();
  }

  void _writeReports(StringBuffer buf) {
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln('# Reports');
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln();
    buf.writeln('report_checks -path_delay min_max > timing.rpt');
    buf.writeln('report_design_area > area.rpt');
    buf.writeln('report_power > power.rpt');
    buf.writeln();
  }

  void _writeOutputs(StringBuffer buf) {
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln('# Write outputs');
    buf.writeln(
      '# ================================================================',
    );
    buf.writeln();
    buf.writeln('write_def \${DEVICE_NAME}_final.def');
    buf.writeln('write_verilog \${DEVICE_NAME}_final.v');
    buf.writeln();
    buf.writeln();
  }
}
