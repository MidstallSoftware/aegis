import '../yosys/tcl_emitter.dart';

/// Emits an OpenROAD TCL script for top-level macro-based place-and-route.
///
/// Tile modules are pre-hardened as macros (with LEF abstracts).
/// This script places them in a grid and routes the inter-tile wiring
/// on upper metal layers.
class OpenroadTclEmitter {
  final String moduleName;
  final int width;
  final int height;
  final int serdesCount;
  final int clockTileCount;
  final int bramColumnInterval;
  final int dspColumnInterval;
  final bool hasConfigClk;
  final bool hasJtag;

  int get totalPads => 2 * width + 2 * height;

  /// Spacing between tile macros (um). Must be large enough for
  /// clock buffer and standard cell placement in routing channels.
  final double macroHaloUm;

  /// Margin around the macro grid edge (um). Room for IO pins
  /// and glue logic placement.
  final double gridMarginUm;

  const OpenroadTclEmitter({
    required this.moduleName,
    required this.width,
    required this.height,
    required this.serdesCount,
    required this.clockTileCount,
    this.bramColumnInterval = 0,
    this.dspColumnInterval = 0,
    this.hasConfigClk = false,
    this.hasJtag = false,
    this.macroHaloUm = 100,
    this.gridMarginUm = 200,
  });

  String generate() {
    final buf = StringBuffer();

    _writeHeader(buf);
    _writeReadInputs(buf);
    _writeFloorplan(buf);
    _writePadring(buf);
    _writePinPlacement(buf);
    _writePowerGrid(buf);
    _writePlacement(buf);
    _writePdnGen(buf);
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
    buf.writeln('# Macro-based hierarchical flow:');
    buf.writeln('# - Tile types are pre-hardened macros (LEF abstracts)');
    buf.writeln('# - Top level places macros and routes inter-tile wiring');
    buf.writeln('#');
    buf.writeln('# Shell variables substituted at build time.');
    buf.writeln();
    // Helper: discover routing layers from loaded tech LEF
    buf.writeln('# Discover routing layers from the PDK tech LEF');
    buf.writeln('proc get_routing_layers {} {');
    buf.writeln('    set layers {}');
    buf.writeln('    set tech [[ord::get_db] getTech]');
    buf.writeln('    foreach layer [\$tech getLayers] {');
    buf.writeln('        if {[\$layer getType] eq "ROUTING"} {');
    buf.writeln('            lappend layers [\$layer getName]');
    buf.writeln('        }');
    buf.writeln('    }');
    buf.writeln('    return \$layers');
    buf.writeln('}');
    buf.writeln();
  }

  void _writeReadInputs(StringBuffer buf) {
    buf.writeln(_section('Read inputs'));

    buf.writeln('read_liberty \$LIB_FILE');
    buf.writeln('read_lef \$TECH_LEF');
    buf.writeln();

    // Read standard cell LEFs
    buf.writeln('# Read standard cell LEFs');
    buf.writeln('foreach lef [glob -directory \$CELL_LEF_DIR *.lef] {');
    buf.writeln('    if {![string match "*tech*" \$lef]} {');
    buf.writeln('        read_lef \$lef');
    buf.writeln('    }');
    buf.writeln('}');
    buf.writeln();
    // Read I/O pad library LEFs (gf180mcu_fd_io: bidir/input/output pads,
    // power pads, padring fillers, corner cell). Only relevant when the
    // chip-level wrapper is being placed; tile-level builds don't supply
    // IO_LEF_DIR.
    buf.writeln('if {[info exists IO_LEF_DIR]} {');
    buf.writeln('    foreach lef [glob -directory \$IO_LEF_DIR *.lef] {');
    buf.writeln('        read_lef \$lef');
    buf.writeln('    }');
    buf.writeln('}');
    buf.writeln('if {[info exists IO_LIB_FILE]} {');
    buf.writeln('    read_liberty \$IO_LIB_FILE');
    buf.writeln('}');
    buf.writeln();

    // Read tile macro LEFs and liberty timing models
    buf.writeln('# Read tile macro LEF abstracts and timing models');
    for (final mod in YosysTclEmitter.tileModules) {
      buf.writeln('if {[file exists \${DEVICE_NAME}_${mod}.lef]} {');
      buf.writeln('    read_lef \${DEVICE_NAME}_${mod}.lef');
      buf.writeln('}');
      buf.writeln('if {[file exists \${DEVICE_NAME}_${mod}.lib]} {');
      buf.writeln('    read_liberty \${DEVICE_NAME}_${mod}.lib');
      buf.writeln('}');
    }
    buf.writeln();

    buf.writeln('read_verilog \$SYNTH_V');
    buf.writeln(
      'if {![info exists TOP_MODULE]} { set TOP_MODULE $moduleName }',
    );
    buf.writeln('link_design \$TOP_MODULE');
    buf.writeln('read_sdc \$SDC_FILE');
    buf.writeln();
    // Wire RC values are required by CTS, repair_design, and the global
    // router's parasitic estimator. Use explicit numeric values rather
    // than -layer so every routing/clock net has a defined R+C the
    // estimator can fall back on, avoiding segfaults inside layerRC
    // when the router asks about a layer we did not parameterize.
    buf.writeln('set_wire_rc -signal -resistance 0.0001 -capacitance 0.0001');
    buf.writeln('set_wire_rc -clock -resistance 0.0001 -capacitance 0.0001');
    buf.writeln();
  }

  void _writeFloorplan(StringBuffer buf) {
    buf.writeln(_section('Floorplan'));

    // Compute die area from macro sizes if available
    buf.writeln('# Determine die area: use explicit setting, or compute from');
    buf.writeln('# tile macro dimensions × grid size.');
    buf.writeln(
      '# When PAD_HEIGHT is set we are doing chip-level integration:',
    );
    buf.writeln('# the core area is inset from the die boundary by PAD_HEIGHT');
    buf.writeln(
      '# on every side so the perimeter is reserved for the padring.',
    );
    buf.writeln('if {[info exists DIE_AREA]} {');
    buf.writeln(
      '    set _core_inset '
      '[expr {[info exists PAD_HEIGHT] ? \$PAD_HEIGHT : 1}]',
    );
    buf.writeln('    initialize_floorplan \\');
    buf.writeln('        -die_area \$DIE_AREA \\');
    buf.writeln(
      '        -core_area "[expr {[lindex \$DIE_AREA 0] + \$_core_inset}] [expr {[lindex \$DIE_AREA 1] + \$_core_inset}] [expr {[lindex \$DIE_AREA 2] - \$_core_inset}] [expr {[lindex \$DIE_AREA 3] - \$_core_inset}]" \\',
    );
    buf.writeln('        -site \$SITE_NAME');
    buf.writeln('} else {');
    buf.writeln('    # Find largest macro to size the die');
    buf.writeln('    set tw 0');
    buf.writeln('    set th 0');
    buf.writeln('    foreach inst [[ord::get_db_block] getInsts] {');
    buf.writeln('        if {[[\$inst getMaster] isBlock]} {');
    buf.writeln(
      '            set mw [ord::dbu_to_microns [[\$inst getMaster] getWidth]]',
    );
    buf.writeln(
      '            set mh [ord::dbu_to_microns [[\$inst getMaster] getHeight]]',
    );
    buf.writeln('            if {\$mw > \$tw} { set tw \$mw }');
    buf.writeln('            if {\$mh > \$th} { set th \$mh }');
    buf.writeln('        }');
    buf.writeln('    }');
    buf.writeln('    if {\$tw > 0} {');
    buf.writeln('        # Count total macro instances to size the die');
    buf.writeln('        set macro_n 0');
    buf.writeln('        foreach inst [[ord::get_db_block] getInsts] {');
    buf.writeln(
      '            if {[[\$inst getMaster] isBlock]} { incr macro_n }',
    );
    buf.writeln('        }');
    buf.writeln('        # Compute grid dimensions from macro count');
    buf.writeln(
      '        set grid_cols [expr {int(sqrt(\$macro_n * \$tw / \$th)) + 1}]',
    );
    buf.writeln(
      '        set grid_rows [expr {(\$macro_n + \$grid_cols - 1) / \$grid_cols}]',
    );
    buf.writeln(
      '        puts "Die grid: \$grid_cols cols x \$grid_rows rows for \$macro_n macros"',
    );
    buf.writeln('        set mfg 0.005');
    buf.writeln(
      '        if {![info exists MACRO_HALO]} { set MACRO_HALO $macroHaloUm }',
    );
    buf.writeln(
      '        if {![info exists GRID_MARGIN]} { set GRID_MARGIN $gridMarginUm }',
    );
    buf.writeln(
      '        set die_w [expr {int(((\$tw + \$MACRO_HALO) * \$grid_cols + 2 * \$GRID_MARGIN) / \$mfg) * \$mfg}]',
    );
    buf.writeln(
      '        set die_h [expr {int(((\$th + \$MACRO_HALO) * \$grid_rows + 2 * \$GRID_MARGIN) / \$mfg) * \$mfg}]',
    );
    buf.writeln(
      '        puts "Computed die area: \${die_w}um x \${die_h}um '
      '(tile: \${tw}um x \${th}um)"',
    );
    buf.writeln('        set margin \$GRID_MARGIN');
    buf.writeln('        initialize_floorplan \\');
    buf.writeln('            -die_area "0 0 \$die_w \$die_h" \\');
    buf.writeln(
      '            -core_area "\$margin \$margin '
      '[expr {\$die_w - \$margin}] [expr {\$die_h - \$margin}]" \\',
    );
    buf.writeln('            -site \$SITE_NAME');
    buf.writeln('    } else {');
    buf.writeln('        # Fallback: utilization-based');
    buf.writeln('        initialize_floorplan \\');
    buf.writeln('            -utilization \$UTILIZATION \\');
    buf.writeln('            -core_space 2 \\');
    buf.writeln('            -site \$SITE_NAME');
    buf.writeln('    }');
    buf.writeln('}');
    buf.writeln();

    buf.writeln('foreach layer [get_routing_layers] {');
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

  /// Place I/O pads around the die perimeter and instantiate corner cells.
  ///
  /// The chip wrapper Verilog already contains the signal-bearing pad
  /// instances. Their physical placement is computed here: pads are
  /// distributed evenly across the four die sides, walking clockwise
  /// starting at the south-west corner. Corner cells are physical-only
  /// instances inserted via odb so they don't need to live in the netlist.
  void _writePadring(StringBuffer buf) {
    buf.writeln(_section('Padring placement'));

    buf.writeln('if {![info exists PAD_HEIGHT]} {');
    buf.writeln('    puts "Skipping padring (PAD_HEIGHT not set)"');
    buf.writeln('} else {');
    buf.writeln('    set die_rect [[ord::get_db_block] getDieArea]');
    buf.writeln('    set die_w [ord::dbu_to_microns [\$die_rect xMax]]');
    buf.writeln('    set die_h [ord::dbu_to_microns [\$die_rect yMax]]');
    buf.writeln('    set pad_h \$PAD_HEIGHT');
    buf.writeln('    set corner \$CORNER_SIZE');
    buf.writeln();

    // Collect every instance whose master is a PAD-class cell. Bidir,
    // input, output, and power pads all have CLASS PAD in the LEF; the
    // db reports their type as PAD or PAD_INPUT/PAD_OUTPUT/PAD_POWER.
    buf.writeln('    set pads {}');
    buf.writeln('    foreach inst [[ord::get_db_block] getInsts] {');
    buf.writeln('        set m [\$inst getMaster]');
    buf.writeln('        set t [\$m getType]');
    buf.writeln('        if {[string match "PAD*" \$t]} {');
    buf.writeln('            lappend pads \$inst');
    buf.writeln('        }');
    buf.writeln('    }');
    buf.writeln('    set npads [llength \$pads]');
    buf.writeln('    puts "Found \$npads pad instances to place"');
    buf.writeln();

    // Distribute round-robin across the 4 sides so power and signal
    // pads end up evenly spread (the wrapper interleaves them in
    // declaration order: bidir IO, then per-port pads, then power pads).
    buf.writeln('    set per_side [expr {(\$npads + 3) / 4}]');
    buf.writeln(
      '    set pad_pitch_x [expr {(\$die_w - 2 * \$corner) / \$per_side}]',
    );
    buf.writeln(
      '    set pad_pitch_y [expr {(\$die_h - 2 * \$corner) / \$per_side}]',
    );
    buf.writeln();

    buf.writeln('    set mfg 0.005');
    buf.writeln('    proc snap_um {v mfg} {');
    buf.writeln('        return [expr {int(\$v / \$mfg) * \$mfg}]');
    buf.writeln('    }');
    buf.writeln();

    buf.writeln('    for {set i 0} {\$i < \$npads} {incr i} {');
    buf.writeln('        set inst [lindex \$pads \$i]');
    buf.writeln('        set side [expr {\$i / \$per_side}]');
    buf.writeln('        if {\$side > 3} { set side 3 }');
    buf.writeln('        set idx [expr {\$i % \$per_side}]');
    buf.writeln('        if {\$side == 0} {');
    buf.writeln('            # South (bottom). Pad in default orientation R0,');
    buf.writeln('            # bond pad faces -Y (towards die edge).');
    buf.writeln(
      '            set x [snap_um [expr {\$corner + \$idx * \$pad_pitch_x}] \$mfg]',
    );
    buf.writeln('            set y 0');
    buf.writeln('            set ori R0');
    buf.writeln('        } elseif {\$side == 1} {');
    buf.writeln('            # East (right). Pad rotated R270 (clockwise 90).');
    buf.writeln('            set x [snap_um [expr {\$die_w - \$pad_h}] \$mfg]');
    buf.writeln(
      '            set y [snap_um [expr {\$corner + \$idx * \$pad_pitch_y}] \$mfg]',
    );
    buf.writeln('            set ori R270');
    buf.writeln('        } elseif {\$side == 2} {');
    buf.writeln('            # North (top). Pad rotated R180.');
    buf.writeln(
      '            set x [snap_um [expr {\$die_w - \$corner - (\$idx + 1) * \$pad_pitch_x}] \$mfg]',
    );
    buf.writeln('            set y [snap_um [expr {\$die_h - \$pad_h}] \$mfg]');
    buf.writeln('            set ori R180');
    buf.writeln('        } else {');
    buf.writeln('            # West (left). Pad rotated R90.');
    buf.writeln('            set x 0');
    buf.writeln(
      '            set y [snap_um [expr {\$die_h - \$corner - (\$idx + 1) * \$pad_pitch_y}] \$mfg]',
    );
    buf.writeln('            set ori R90');
    buf.writeln('        }');
    buf.writeln(
      '        \$inst setLocation [ord::microns_to_dbu \$x] [ord::microns_to_dbu \$y]',
    );
    buf.writeln('        \$inst setLocationOrient \$ori');
    buf.writeln('        \$inst setPlacementStatus FIRM');
    buf.writeln('    }');
    buf.writeln(
      '    puts "Placed \$npads pads (\$per_side per side, pitch x=\$pad_pitch_x y=\$pad_pitch_y)"',
    );
    buf.writeln();

    // Corner cells. These are physical-only instances created via odb so
    // they don't need to appear in the wrapper netlist.
    buf.writeln(
      '    set corner_master [[ord::get_db] findMaster \$PAD_CORNER]',
    );
    buf.writeln('    if {\$corner_master ne "NULL"} {');
    buf.writeln('        set block [ord::get_db_block]');
    buf.writeln(
      '        proc place_corner {block master name x_um y_um ori} {',
    );
    buf.writeln(
      '            set inst [odb::dbInst_create \$block \$master \$name]',
    );
    buf.writeln(
      '            \$inst setLocation [ord::microns_to_dbu \$x_um] '
      '[ord::microns_to_dbu \$y_um]',
    );
    buf.writeln('            \$inst setLocationOrient \$ori');
    buf.writeln('            \$inst setPlacementStatus FIRM');
    buf.writeln('        }');
    buf.writeln(
      '        place_corner \$block \$corner_master "corner_bl" 0 0 R0',
    );
    buf.writeln(
      '        place_corner \$block \$corner_master "corner_br" '
      '[expr {\$die_w - \$corner}] 0 R270',
    );
    buf.writeln(
      '        place_corner \$block \$corner_master "corner_tr" '
      '[expr {\$die_w - \$corner}] [expr {\$die_h - \$corner}] R180',
    );
    buf.writeln(
      '        place_corner \$block \$corner_master "corner_tl" '
      '0 [expr {\$die_h - \$corner}] R90',
    );
    buf.writeln('        puts "Placed 4 corner cells"');
    buf.writeln('    } else {');
    buf.writeln('        puts "WARNING: corner cell \$PAD_CORNER not loaded"');
    buf.writeln('    }');
    buf.writeln('}');
    buf.writeln();
  }

  void _writePinPlacement(StringBuffer buf) {
    buf.writeln(_section('Pin placement'));

    final westPins = <String>['clk', 'reset', 'configDone'];
    if (hasConfigClk) westPins.add('configClk');
    westPins.addAll([
      'configRead_en',
      'configRead_addr\\[*\\]',
      'configRead_data\\[*\\]',
    ]);
    if (hasJtag) {
      westPins.addAll(['tck', 'tms', 'tdi', 'tdo', 'trst']);
    }

    final eastPins = <String>[];
    if (serdesCount > 0) {
      eastPins.addAll([
        'serialIn\\[*\\]',
        'serialOut\\[*\\]',
        'txReady\\[*\\]',
        'rxValid\\[*\\]',
      ]);
    }
    if (clockTileCount > 0) {
      eastPins.addAll(['clkOut\\[*\\]', 'clkLocked\\[*\\]']);
    }

    // place_pins assigns physical locations to top-level ports. The
    // chip-level wrapper has only VDD/VSS as ports (bond pads are the
    // signal boundary), and those are power nets that OpenROAD's
    // global_connect handles separately, so place_pins isn't needed
    // when PAD_HEIGHT is set.
    buf.writeln('if {![info exists PAD_HEIGHT]} {');
    _writeLayerDetection(buf);
    buf.writeln(
      '    place_pins -hor_layers \$hor_layer -ver_layers \$ver_layer',
    );
    buf.writeln('} else {');
    buf.writeln(
      '    puts "Skipping place_pins (chip wrapper has no signal ports)"',
    );
    buf.writeln('}');
    buf.writeln();
  }

  void _writePowerGrid(StringBuffer buf) {
    buf.writeln(_section('Power grid'));

    buf.writeln('add_global_connection -net VDD -pin_pattern VDD -power');
    buf.writeln('add_global_connection -net VSS -pin_pattern VSS -ground');
    buf.writeln('global_connect');
    buf.writeln();
  }

  /// Generate PDN after macros are placed and fixed.
  void _writePdnGen(StringBuffer buf) {
    buf.writeln(_section('Power delivery network'));

    buf.writeln('if {[info exists PDN_RAIL_LAYER]} {');
    buf.writeln('    set_voltage_domain -name CORE -power VDD -ground VSS');
    buf.writeln();
    buf.writeln(
      '    # Standard cell grid: M1 followpins + M4 vertical + M5 horizontal',
    );
    buf.writeln('    define_pdn_grid -name stdcell_grid \\');
    buf.writeln('        -starts_with POWER -voltage_domain CORE');
    buf.writeln();
    buf.writeln('    add_pdn_stripe -grid stdcell_grid \\');
    buf.writeln(
      '        -layer \$PDN_RAIL_LAYER -width \$PDN_RAIL_WIDTH -followpins',
    );
    buf.writeln();
    buf.writeln('    add_pdn_stripe -grid stdcell_grid \\');
    buf.writeln('        -layer \$PDN_VERTICAL_LAYER -width \$PDN_VWIDTH \\');
    buf.writeln('        -pitch \$PDN_VPITCH -offset \$PDN_VOFFSET \\');
    buf.writeln('        -spacing \$PDN_VSPACING -starts_with POWER');
    buf.writeln();
    buf.writeln('    add_pdn_stripe -grid stdcell_grid \\');
    buf.writeln('        -layer \$PDN_HORIZONTAL_LAYER -width \$PDN_HWIDTH \\');
    buf.writeln('        -pitch \$PDN_HPITCH -offset \$PDN_HOFFSET \\');
    buf.writeln('        -spacing \$PDN_HSPACING -starts_with POWER');
    buf.writeln();
    buf.writeln('    # Stitch the three strap layers together');
    buf.writeln('    add_pdn_connect -grid stdcell_grid \\');
    buf.writeln('        -layers "\$PDN_RAIL_LAYER \$PDN_VERTICAL_LAYER"');
    buf.writeln('    add_pdn_connect -grid stdcell_grid \\');
    buf.writeln(
      '        -layers "\$PDN_VERTICAL_LAYER \$PDN_HORIZONTAL_LAYER"',
    );
    buf.writeln();
    buf.writeln('    # Macro grid: bind to each tile macro\'s exposed M1');
    buf.writeln('    # power pins. -grid_over_pg_pins tells pdngen to use');
    buf.writeln('    # the macro\'s existing PG pin locations as via drops,');
    buf.writeln('    # so the M4/M5 straps that pass over the macro can land');
    buf.writeln('    # vias to power the cells inside.');
    buf.writeln('    define_pdn_grid -name macro_grid -macro -default \\');
    buf.writeln('        -starts_with POWER -voltage_domain CORE \\');
    buf.writeln('        -grid_over_pg_pins');
    buf.writeln('    add_pdn_connect -grid macro_grid \\');
    buf.writeln('        -layers "\$PDN_RAIL_LAYER \$PDN_VERTICAL_LAYER"');
    buf.writeln('    add_pdn_connect -grid macro_grid \\');
    buf.writeln(
      '        -layers "\$PDN_VERTICAL_LAYER \$PDN_HORIZONTAL_LAYER"',
    );
    buf.writeln();
    buf.writeln('    pdngen');
    buf.writeln('}');
    buf.writeln();
  }

  void _writePlacement(StringBuffer buf) {
    buf.writeln(_section('Placement'));

    // Count and report unplaced macros
    buf.writeln('# Detect macros');
    buf.writeln('set macro_count 0');
    buf.writeln('foreach inst [[ord::get_db_block] getInsts] {');
    buf.writeln('    if {[[\$inst getMaster] isBlock]} {');
    buf.writeln('        incr macro_count');
    buf.writeln('    }');
    buf.writeln('}');
    buf.writeln('puts "Detected \$macro_count macro instances"');
    buf.writeln();

    buf.writeln('if {\$macro_count > 0} {');
    buf.writeln(
      '    if {![info exists MACRO_HALO]} { set MACRO_HALO $macroHaloUm }',
    );
    buf.writeln(
      '    if {![info exists GRID_MARGIN]} { set GRID_MARGIN $gridMarginUm }',
    );
    buf.writeln('    set halo \$MACRO_HALO');
    buf.writeln('    set margin \$GRID_MARGIN');
    buf.writeln();

    // Group macros by master name
    buf.writeln('    # Group macros by type');
    buf.writeln('    array set macro_groups {}');
    buf.writeln('    foreach inst [[ord::get_db_block] getInsts] {');
    buf.writeln('        if {[[\$inst getMaster] isBlock]} {');
    buf.writeln('            set mname [[\$inst getMaster] getName]');
    buf.writeln('            lappend macro_groups(\$mname) \$inst');
    buf.writeln('        }');
    buf.writeln('    }');
    buf.writeln();
    buf.writeln('    foreach type [array names macro_groups] {');
    buf.writeln('        set n [llength \$macro_groups(\$type)]');
    buf.writeln('        set m [[lindex \$macro_groups(\$type) 0] getMaster]');
    buf.writeln('        set w [ord::dbu_to_microns [\$m getWidth]]');
    buf.writeln('        set h [ord::dbu_to_microns [\$m getHeight]]');
    buf.writeln('        puts "  \$type: \$n instances (\${w}um x \${h}um)"');
    buf.writeln('    }');
    buf.writeln();

    // Use the *core* area for placement: with chip-level integration
    // the padring occupies a PAD_HEIGHT strip between core and die, so
    // tile macros must be shifted inwards by the core origin and sized
    // against the core dimensions.
    buf.writeln('    set core_rect [[ord::get_db_block] getCoreArea]');
    buf.writeln('    set core_xmin [ord::dbu_to_microns [\$core_rect xMin]]');
    buf.writeln('    set core_ymin [ord::dbu_to_microns [\$core_rect yMin]]');
    buf.writeln('    set core_xmax [ord::dbu_to_microns [\$core_rect xMax]]');
    buf.writeln('    set core_ymax [ord::dbu_to_microns [\$core_rect yMax]]');
    buf.writeln('    set die_w [expr {\$core_xmax - \$core_xmin}]');
    buf.writeln('    set die_h [expr {\$core_ymax - \$core_ymin}]');
    buf.writeln();
    // place_inst translates a core-relative (x_um, y_um) location to the
    // absolute die coordinate that OpenROAD wants. Using this helper
    // means the rest of the placement logic can keep speaking in
    // core-relative terms even when the core has been inset.
    buf.writeln('    proc place_inst {inst x_um y_um} {');
    buf.writeln('        upvar core_xmin xoff core_ymin yoff');
    buf.writeln(
      '        \$inst setLocation '
      '[ord::microns_to_dbu [expr {\$x_um + \$xoff}]] '
      '[ord::microns_to_dbu [expr {\$y_um + \$yoff}]]',
    );
    buf.writeln('        \$inst setPlacementStatus FIRM');
    buf.writeln('    }');
    buf.writeln();

    // Place fabric tiles (Tile, BramTile, DspBasicTile) in main grid
    // Each type uses its own height, packed into columns
    buf.writeln('    # Place fabric tiles in a grid');
    buf.writeln('    # Get Tile dimensions for the main grid pitch');
    buf.writeln('    set tile_w 0');
    buf.writeln('    set tile_h 0');
    buf.writeln('    if {[info exists macro_groups(Tile)]} {');
    buf.writeln(
      '        set tile_w [ord::dbu_to_microns [[[lindex \$macro_groups(Tile) 0] getMaster] getWidth]]',
    );
    buf.writeln(
      '        set tile_h [ord::dbu_to_microns [[[lindex \$macro_groups(Tile) 0] getMaster] getHeight]]',
    );
    buf.writeln('    }');
    buf.writeln('    set tile_px [expr {\$tile_w + \$halo}]');
    buf.writeln('    set tile_py [expr {\$tile_h + \$halo}]');
    buf.writeln();

    // Compute fabric grid columns from die width
    // Reserve right edge for non-fabric macros (Clock, SerDes, etc.)
    buf.writeln('    set edge_reserve 250');
    buf.writeln(
      '    set fabric_w [expr {\$die_w - 2 * \$margin - \$edge_reserve}]',
    );
    buf.writeln('    set fabric_cols [expr {int(\$fabric_w / \$tile_px)}]');
    buf.writeln('    if {\$fabric_cols < 1} { set fabric_cols 1 }');
    buf.writeln();

    // Place Tile, BramTile, DspBasicTile in fabric grid
    buf.writeln('    set cur_x \$margin');
    buf.writeln('    set cur_y \$margin');
    buf.writeln('    set col 0');
    buf.writeln('    set placed 0');
    buf.writeln();

    // Place fabric tiles column by column, matching the FPGA fabric layout.
    // BRAM columns at bramColumnInterval, DSP at dspColumnInterval,
    // remaining columns are LUT tiles. Each column type uses its own width.
    buf.writeln(
      '    # Build column-major placement matching FPGA fabric layout',
    );
    buf.writeln('    # Queues for each tile type');
    buf.writeln(
      '    set tile_q [expr {[info exists macro_groups(Tile)] ? \$macro_groups(Tile) : {}}]',
    );
    buf.writeln(
      '    set bram_q [expr {[info exists macro_groups(BramTile)] ? \$macro_groups(BramTile) : {}}]',
    );
    buf.writeln(
      '    set dsp_q [expr {[info exists macro_groups(DspBasicTile)] ? \$macro_groups(DspBasicTile) : {}}]',
    );
    buf.writeln();
    buf.writeln('    # Compute column types and x positions');
    buf.writeln('    set cur_x \$margin');
    buf.writeln('    set fabric_height ${height}');
    buf.writeln('    set col_x_list {}');
    buf.writeln('    set col_type_list {}');
    buf.writeln('    for {set c 0} {\$c < ${width}} {incr c} {');

    // Determine column type using same logic as Dart fabric
    buf.writeln('        set ctype "Tile"');
    if (bramColumnInterval > 0) {
      buf.writeln(
        '        if {$bramColumnInterval > 0 && '
        '(\$c - $bramColumnInterval) >= 0 && '
        '((\$c - $bramColumnInterval) % ($bramColumnInterval + 1)) == 0} {',
      );
      buf.writeln('            set ctype "BramTile"');
      buf.writeln('        }');
    }
    if (dspColumnInterval > 0) {
      buf.writeln(
        '        if {\$ctype eq "Tile" && $dspColumnInterval > 0 && '
        '(\$c - $dspColumnInterval) >= 0 && '
        '((\$c - $dspColumnInterval) % ($dspColumnInterval + 1)) == 0} {',
      );
      buf.writeln('            set ctype "DspBasicTile"');
      buf.writeln('        }');
    }

    buf.writeln('        lappend col_type_list \$ctype');
    buf.writeln('        lappend col_x_list \$cur_x');
    buf.writeln();
    buf.writeln('        # Advance x by this column type\'s width');
    buf.writeln('        switch \$ctype {');
    buf.writeln('            Tile { set cw \$tile_w }');
    buf.writeln('            BramTile {');
    buf.writeln('                if {[llength \$bram_q] > 0} {');
    buf.writeln(
      '                    set cw [ord::dbu_to_microns [[[lindex \$bram_q 0] getMaster] getWidth]]',
    );
    buf.writeln('                } else { set cw \$tile_w }');
    buf.writeln('            }');
    buf.writeln('            DspBasicTile {');
    buf.writeln('                if {[llength \$dsp_q] > 0} {');
    buf.writeln(
      '                    set cw [ord::dbu_to_microns [[[lindex \$dsp_q 0] getMaster] getWidth]]',
    );
    buf.writeln('                } else { set cw \$tile_w }');
    buf.writeln('            }');
    buf.writeln('        }');
    buf.writeln('        set cur_x [expr {\$cur_x + \$cw + \$halo}]');
    buf.writeln('    }');
    buf.writeln();

    // Now place tiles column by column, row by row
    buf.writeln('    # Place tiles in fabric grid');
    buf.writeln('    set placed 0');
    buf.writeln('    for {set c 0} {\$c < ${width}} {incr c} {');
    buf.writeln('        set ctype [lindex \$col_type_list \$c]');
    buf.writeln('        set cx [lindex \$col_x_list \$c]');
    buf.writeln('        for {set r 0} {\$r < \$fabric_height} {incr r} {');
    buf.writeln('            set cy [expr {\$margin + \$r * \$tile_py}]');
    buf.writeln('            switch \$ctype {');
    buf.writeln('                Tile {');
    buf.writeln('                    if {[llength \$tile_q] > 0} {');
    buf.writeln('                        set inst [lindex \$tile_q 0]');
    buf.writeln('                        set tile_q [lrange \$tile_q 1 end]');
    buf.writeln('                        place_inst \$inst \$cx \$cy');
    buf.writeln('                        incr placed');
    buf.writeln('                    }');
    buf.writeln('                }');
    buf.writeln('                BramTile {');
    buf.writeln('                    if {[llength \$bram_q] > 0} {');
    buf.writeln('                        set inst [lindex \$bram_q 0]');
    buf.writeln('                        set bram_q [lrange \$bram_q 1 end]');
    buf.writeln('                        place_inst \$inst \$cx \$cy');
    buf.writeln('                        incr placed');
    buf.writeln('                    }');
    buf.writeln('                }');
    buf.writeln('                DspBasicTile {');
    buf.writeln('                    if {[llength \$dsp_q] > 0} {');
    buf.writeln('                        set inst [lindex \$dsp_q 0]');
    buf.writeln('                        set dsp_q [lrange \$dsp_q 1 end]');
    buf.writeln('                        place_inst \$inst \$cx \$cy');
    buf.writeln('                        incr placed');
    buf.writeln('                    }');
    buf.writeln('                }');
    buf.writeln('            }');
    buf.writeln('        }');
    buf.writeln('    }');
    buf.writeln(
      '    set fabric_top [expr {\$margin + \$fabric_height * \$tile_py}]',
    );
    buf.writeln(
      '    puts "Placed \$placed fabric tiles in ${width} cols x \$fabric_height rows"',
    );
    buf.writeln();

    // Place IO tiles along the edges of the fabric grid
    buf.writeln('    # Place IO tiles along fabric perimeter');
    buf.writeln('    if {[info exists macro_groups(IOTile)]} {');
    buf.writeln(
      '        set io_h [ord::dbu_to_microns [[[lindex \$macro_groups(IOTile) 0] getMaster] getHeight]]',
    );
    buf.writeln(
      '        set io_w [ord::dbu_to_microns [[[lindex \$macro_groups(IOTile) 0] getMaster] getWidth]]',
    );
    buf.writeln('        set io_px [expr {\$io_w + \$halo}]');
    buf.writeln('        set io_idx 0');
    buf.writeln('        set io_count [llength \$macro_groups(IOTile)]');
    buf.writeln('        # Place along bottom edge');
    buf.writeln('        set io_y [expr {\$margin - \$io_h - \$halo}]');
    buf.writeln('        if {\$io_y < 0} { set io_y 0 }');
    buf.writeln(
      '        for {set i 0} {\$i < \$fabric_cols && \$io_idx < \$io_count} {incr i} {',
    );
    buf.writeln('            set io_x [expr {\$margin + \$i * \$tile_px}]');
    buf.writeln(
      '            place_inst [lindex \$macro_groups(IOTile) \$io_idx] '
      '\$io_x \$io_y',
    );
    buf.writeln('            incr io_idx');
    buf.writeln('        }');
    buf.writeln('        # Place along top edge');
    buf.writeln('        set io_y \$fabric_top');
    buf.writeln(
      '        for {set i 0} {\$i < \$fabric_cols && \$io_idx < \$io_count} {incr i} {',
    );
    buf.writeln('            set io_x [expr {\$margin + \$i * \$tile_px}]');
    buf.writeln(
      '            place_inst [lindex \$macro_groups(IOTile) \$io_idx] '
      '\$io_x \$io_y',
    );
    buf.writeln('            incr io_idx');
    buf.writeln('        }');
    buf.writeln('        # Place remaining IO tiles along right edge');
    buf.writeln(
      '        set io_x [expr {\$margin + \$fabric_cols * \$tile_px}]',
    );
    buf.writeln('        set io_row 0');
    buf.writeln('        while {\$io_idx < \$io_count} {');
    buf.writeln(
      '            set io_y [expr {\$margin + \$io_row * (\$io_h + \$halo)}]',
    );
    buf.writeln(
      '            place_inst [lindex \$macro_groups(IOTile) \$io_idx] '
      '\$io_x \$io_y',
    );
    buf.writeln('            incr io_idx');
    buf.writeln('            incr io_row');
    buf.writeln('        }');
    buf.writeln('        puts "Placed \$io_count IO tiles around perimeter"');
    buf.writeln('    }');
    buf.writeln();

    // Place edge macros (Clock, SerDes, FabricConfigLoader) along right edge
    // Place SerDes above the fabric grid
    buf.writeln('    # Place SerDes tiles above the fabric grid');
    buf.writeln('    if {[info exists macro_groups(SerDesTile)]} {');
    buf.writeln('        set serdes_x \$margin');
    buf.writeln('        set serdes_y [expr {\$fabric_top + \$halo}]');
    buf.writeln('        foreach inst \$macro_groups(SerDesTile) {');
    buf.writeln(
      '            set mw [ord::dbu_to_microns [[\$inst getMaster] getWidth]]',
    );
    buf.writeln(
      '            set mh [ord::dbu_to_microns [[\$inst getMaster] getHeight]]',
    );
    buf.writeln('            place_inst \$inst \$serdes_x \$serdes_y');
    buf.writeln(
      '            puts "Placed SerDesTile at \${serdes_x}um x \${serdes_y}um"',
    );
    buf.writeln('            set serdes_x [expr {\$serdes_x + \$mw + \$halo}]');
    buf.writeln('        }');
    buf.writeln('    }');
    buf.writeln();

    // Place Clock and ConfigLoader on the right edge
    buf.writeln('    # Place Clock and ConfigLoader on right edge');
    buf.writeln('    set edge_x [expr {\$die_w - \$margin}]');
    buf.writeln('    set edge_y \$margin');
    buf.writeln('    foreach type {ClockTile FabricConfigLoader JtagTap} {');
    buf.writeln('        if {[info exists macro_groups(\$type)]} {');
    buf.writeln('            foreach inst \$macro_groups(\$type) {');
    buf.writeln(
      '                set mw [ord::dbu_to_microns [[\$inst getMaster] getWidth]]',
    );
    buf.writeln(
      '                set mh [ord::dbu_to_microns [[\$inst getMaster] getHeight]]',
    );
    buf.writeln('                set x [expr {\$edge_x - \$mw}]');
    buf.writeln('                place_inst \$inst \$x \$edge_y');
    buf.writeln('                set edge_y [expr {\$edge_y + \$mh + \$halo}]');
    buf.writeln(
      '                puts "Placed \$type at \${x}um x [expr {\$edge_y - \$mh - \$halo}]um"',
    );
    buf.writeln('            }');
    buf.writeln('        }');
    buf.writeln('    }');
    buf.writeln();

    buf.writeln('    # Cut standard cell rows around placed macros');
    buf.writeln('    cut_rows');
    buf.writeln('}');
    buf.writeln();

    // Then place remaining standard cells (glue logic)
    buf.writeln('# Place remaining standard cells');
    buf.writeln(
      'if {![info exists PLACEMENT_DENSITY]} { set PLACEMENT_DENSITY 0.1 }',
    );
    buf.writeln('global_placement -density \$PLACEMENT_DENSITY');
    buf.writeln('detailed_placement');
    buf.writeln();
  }

  void _writeCts(StringBuffer buf) {
    buf.writeln(_section('Clock tree synthesis'));

    buf.writeln('estimate_parasitics -placement');
    buf.writeln();
    buf.writeln('set cts_bufs {}');
    buf.writeln('foreach sz {2 4 8 16} {');
    buf.writeln('    set cell_name \${CELL_LIB}__clkbuf_\$sz');
    buf.writeln('    lappend cts_bufs \$cell_name');
    buf.writeln('}');
    buf.writeln('clock_tree_synthesis -buf_list \$cts_bufs');
    buf.writeln();
    buf.writeln('detailed_placement');
    buf.writeln();

    // Filler cell insertion: fillcap first (decoupling capacitance),
    // then plain fill for the smaller leftover gaps. Largest first so
    // big gaps consume one big cell.
    buf.writeln('set fillers {}');
    buf.writeln('foreach sz {64 32 16 8 4} {');
    buf.writeln('    lappend fillers \${CELL_LIB}__fillcap_\$sz');
    buf.writeln('}');
    buf.writeln('foreach sz {64 32 16 8 4 2 1} {');
    buf.writeln('    lappend fillers \${CELL_LIB}__fill_\$sz');
    buf.writeln('}');
    buf.writeln('filler_placement \$fillers');
    buf.writeln();
  }

  void _writeRouting(StringBuffer buf) {
    buf.writeln(_section('Routing'));

    // Top-level signals route on Metal2 through Metal4. The chip-level
    // pad cells expose their internal A/Y/OE pins on Metal2 - that is
    // where signals enter and leave the pad. The Metal5 PAD pin is the
    // physical bond-wire attachment point and intentionally has no
    // internal access (it's reached by the bond wire externally), so
    // capping signal routing at Metal4 keeps detailed_route from
    // failing pin-access checks on those PAD pins.
    buf.writeln('set_routing_layers -signal Metal2-Metal4');
    buf.writeln('# Apply per-layer routing capacity adjustments');
    buf.writeln('if {[array exists LAYER_ADJ]} {');
    buf.writeln('    foreach layer [array names LAYER_ADJ] {');
    buf.writeln(
      '        set_global_routing_layer_adjustment \$layer \$LAYER_ADJ(\$layer)',
    );
    buf.writeln('    }');
    buf.writeln('}');
    // -congestion_iterations 0 skips the rip-up-and-reroute pass that
    // calls parasitic estimation (which is segfaulting in
    // MakeWireParasitics::layerRC for this chip-level design). The
    // initial route still runs; detailed_route handles the cleanup.
    buf.writeln('global_route -allow_congestion -congestion_iterations 0');
    buf.writeln();
    buf.writeln('# Save global-routed DEF (guaranteed output)');
    buf.writeln('write_def \${DEVICE_NAME}_grouted.def');
    buf.writeln();
    buf.writeln(
      'if {![info exists DROUTE_END_ITER]} { set DROUTE_END_ITER 32 }',
    );
    // -top_routing_layer caps detailed_route at Metal4 so it never
    // looks at Metal5 (where the bond-pad PAD pins live, and where
    // we deliberately do not have internal access). Without this
    // restriction the router fails with DRT-0073 on PAD pins.
    buf.writeln(
      'detailed_route -droute_end_iter \$DROUTE_END_ITER '
      '-or_seed 42 -or_k 3 '
      '-bottom_routing_layer Metal2 -top_routing_layer Metal4 '
      '-output_drc \${DEVICE_NAME}_drc.rpt',
    );
    buf.writeln();

    // Antenna check + repair via layer-bumping only. We reclassify any
    // ANTENNACELL master to plain CORE so repair_antennas cannot insert
    // diode cells (the gf180mcu __antenna cell has class ANTENNACELL but
    // we don't want it instantiated).
    buf.writeln('foreach lib [[ord::get_db] getLibs] {');
    buf.writeln('    foreach mast [\$lib getMasters] {');
    buf.writeln('        if {[\$mast getType] eq "CORE_ANTENNACELL"} {');
    buf.writeln('            \$mast setType "CORE"');
    buf.writeln('        }');
    buf.writeln('    }');
    buf.writeln('}');
    buf.writeln('check_antennas -report_file antenna_pre.rpt');
    // repair_antennas does its own incremental routing for layer-bumping;
    // a follow-up detailed_route would conflict with M4 pin access on the
    // tile macros (DRT-1231) so we trust repair_antennas to leave the
    // design routed.
    buf.writeln('repair_antennas');
    buf.writeln('check_antennas -report_file antenna.rpt');
    buf.writeln();
  }

  void _writeDensityFill(StringBuffer buf) {
    buf.writeln(_section('Density fill'));

    buf.writeln(r'density_fill -rules $FILL_CONFIG');
    buf.writeln();
  }

  void _writeReports(StringBuffer buf) {
    buf.writeln(_section('Reports'));

    buf.writeln('report_checks -path_delay min_max > timing.rpt');
    buf.writeln('report_design_area > area.rpt');
    buf.writeln('report_power > power.rpt');
    buf.writeln();
  }

  void _writeOutputs(StringBuffer buf) {
    buf.writeln(_section('Write outputs'));

    buf.writeln('write_def \${DEVICE_NAME}_final.def');
    buf.writeln('write_verilog \${DEVICE_NAME}_final.v');
    buf.writeln();
  }

  void _writeLayerDetection(StringBuffer buf) {
    // Push top-level pins up to Metal3 (hor) / Metal4 (ver). Tile macros
    // also expose pins on these layers, so inter-tile routing stays on
    // higher layers and avoids saturating M2/M3.
    buf.writeln('set hor_layer ""');
    buf.writeln('set ver_layer ""');
    buf.writeln('set skip_first_hor 1');
    buf.writeln('set skip_first_ver 1');
    buf.writeln('foreach layer [get_routing_layers] {');
    buf.writeln(
      '    if {![catch {set tl '
      '[[[ord::get_db] getTech] findLayer \$layer]}]} {',
    );
    buf.writeln('        if {\$tl ne "NULL"} {');
    buf.writeln('            set dir [\$tl getDirection]');
    buf.writeln('            if {\$dir eq "HORIZONTAL" && \$skip_first_hor} {');
    buf.writeln('                set skip_first_hor 0');
    buf.writeln(
      '            } elseif {\$dir eq "HORIZONTAL" && \$hor_layer eq ""} {',
    );
    buf.writeln('                set hor_layer \$layer');
    buf.writeln('            }');
    buf.writeln('            if {\$dir eq "VERTICAL" && \$skip_first_ver} {');
    buf.writeln('                set skip_first_ver 0');
    buf.writeln(
      '            } elseif {\$dir eq "VERTICAL" && \$ver_layer eq ""} {',
    );
    buf.writeln('                set ver_layer \$layer');
    buf.writeln('            }');
    buf.writeln('        }');
    buf.writeln('    }');
    buf.writeln('}');
    buf.writeln('if {\$hor_layer eq ""} { set hor_layer Metal3 }');
    buf.writeln('if {\$ver_layer eq ""} { set ver_layer Metal4 }');
    buf.writeln('puts "Pin layers: hor=\$hor_layer ver=\$ver_layer"');
  }

  String _section(String title) =>
      '# ================================================================\n'
      '# $title\n'
      '# ================================================================\n';
}
