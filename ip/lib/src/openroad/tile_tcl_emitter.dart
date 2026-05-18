/// Emits an OpenROAD TCL script to PnR a single tile type as a hard macro.
///
/// The resulting macro has deterministic pin positions on all 4 edges
/// so adjacent tiles connect correctly when placed in a grid.
class OpenroadTileTclEmitter {
  final String deviceName;
  final int tracks;

  const OpenroadTileTclEmitter({
    required this.deviceName,
    required this.tracks,
  });

  /// Generate a PnR script for a single tile module.
  String generateTilePnr(String tileModule) {
    final buf = StringBuffer();

    buf.writeln('# OpenROAD PnR script for $tileModule macro');
    buf.writeln('# Auto-generated - produces a hard macro for tile-based PnR');
    buf.writeln();

    // Helper: discover routing layers from the PDK tech LEF
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

    // Read inputs
    buf.writeln('read_liberty \$LIB_FILE');
    buf.writeln('read_lef \$TECH_LEF');
    buf.writeln();
    buf.writeln('foreach lef [glob -directory \$CELL_LEF_DIR *.lef] {');
    buf.writeln('    if {![string match "*tech*" \$lef]} {');
    buf.writeln('        read_lef \$lef');
    buf.writeln('    }');
    buf.writeln('}');
    buf.writeln();
    buf.writeln('read_verilog \${DEVICE_NAME}_${tileModule}_synth.v');
    buf.writeln('link_design $tileModule');
    buf.writeln();

    buf.writeln('create_clock [get_ports clk] -name clk -period \$CLK_PERIOD');
    buf.writeln();

    buf.writeln('if {[info exists TILE_DIE_W] && [info exists TILE_DIE_H]} {');
    buf.writeln('    initialize_floorplan \\');
    buf.writeln('        -die_area "0 0 \$TILE_DIE_W \$TILE_DIE_H" \\');
    buf.writeln(
      '        -core_area "1 1 [expr {\$TILE_DIE_W - 1}] [expr {\$TILE_DIE_H - 1}]" \\',
    );
    buf.writeln('        -site \$SITE_NAME');
    buf.writeln('} else {');
    buf.writeln('    initialize_floorplan \\');
    buf.writeln('        -utilization \$TILE_UTIL \\');
    buf.writeln('        -core_space 1 \\');
    buf.writeln('        -site \$SITE_NAME');
    buf.writeln('}');
    buf.writeln();

    // Routing tracks
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

    buf.writeln('# Pin placement on edges for inter-tile connectivity');
    _writeLayerDetection(buf);
    buf.writeln('place_pins -hor_layers \$hor_layer -ver_layers \$ver_layer');
    buf.writeln();

    // Power
    buf.writeln('add_global_connection -net VDD -pin_pattern VDD -power');
    buf.writeln('add_global_connection -net VSS -pin_pattern VSS -ground');
    buf.writeln('global_connect');
    buf.writeln();

    // Power delivery network for tile.
    //
    // The tile owns its own M1 + M4 power grid. The abstract LEF written
    // at the end of this script exposes the M4 power straps as VDD/VSS
    // pins on the tile boundary, so the top-level PDN can land vias from
    // its M5 horizontal straps onto these M4 rails.
    //
    // Top metal stays at M4: M5 is reserved for the top-level horizontal
    // power straps so we never compete with the top PDN inside macros.
    buf.writeln('if {[info exists PDN_RAIL_LAYER]} {');
    buf.writeln('    set_voltage_domain -name CORE -power VDD -ground VSS');
    buf.writeln('    define_pdn_grid -name stdcell_grid \\');
    buf.writeln('        -starts_with POWER -voltage_domain CORE');
    buf.writeln('    add_pdn_stripe -grid stdcell_grid \\');
    buf.writeln(
      '        -layer \$PDN_RAIL_LAYER -width \$PDN_RAIL_WIDTH -followpins',
    );
    buf.writeln('    add_pdn_stripe -grid stdcell_grid \\');
    buf.writeln('        -layer \$PDN_VERTICAL_LAYER -width \$PDN_VWIDTH \\');
    buf.writeln('        -pitch \$PDN_VPITCH -offset \$PDN_VOFFSET \\');
    buf.writeln('        -spacing \$PDN_VSPACING -starts_with POWER');
    buf.writeln('    add_pdn_connect -grid stdcell_grid \\');
    buf.writeln('        -layers "\$PDN_RAIL_LAYER \$PDN_VERTICAL_LAYER"');
    buf.writeln('    pdngen');
    buf.writeln('}');
    buf.writeln();

    // Tap cell and endcap insertion (required for well taps - DF.13).
    // Only apply to tiles large enough to absorb the tap cells without
    // breaking placement legalization.
    buf.writeln('set die_area [ord::get_die_area]');
    buf.writeln(
      'set die_w [expr {[lindex \$die_area 2] - [lindex \$die_area 0]}]',
    );
    buf.writeln(
      'set die_h [expr {[lindex \$die_area 3] - [lindex \$die_area 1]}]',
    );
    buf.writeln('if {min(\$die_w, \$die_h) > 60} {');
    buf.writeln('    tapcell -tapcell_master \${CELL_LIB}__filltie \\');
    buf.writeln('        -endcap_master \${CELL_LIB}__endcap -distance 15');
    buf.writeln('}');
    buf.writeln();

    // Add cell padding to prevent M1.2a violations at abutment.
    // Only apply when utilization is low enough to absorb the padding.
    buf.writeln('if {min(\$die_w, \$die_h) > 200} {');
    buf.writeln('    set_placement_padding -global -left 1 -right 1');
    buf.writeln('}');

    // Placement
    buf.writeln(
      'if {![info exists TILE_PLACEMENT_DENSITY]} '
      '{ set TILE_PLACEMENT_DENSITY \$TILE_UTIL }',
    );
    buf.writeln('global_placement -density \$TILE_PLACEMENT_DENSITY');
    buf.writeln('detailed_placement');
    buf.writeln();

    // CTS
    buf.writeln('estimate_parasitics -placement');
    buf.writeln('set cts_bufs {}');
    buf.writeln('foreach sz {2 4 8} {');
    buf.writeln('    set cell_name \${CELL_LIB}__clkbuf_\$sz');
    buf.writeln('    lappend cts_bufs \$cell_name');
    buf.writeln('}');
    buf.writeln('clock_tree_synthesis -buf_list \$cts_bufs');
    buf.writeln('detailed_placement');
    buf.writeln();

    // Filler cell insertion: closes gaps between standard cells so
    // VDD/VSS rails are continuous. Fillcap cells are tried first so big
    // gaps get decoupling capacitance, then plain fill cells handle the
    // small leftover gaps where fillcap doesn't go below 4 sites wide.
    buf.writeln('set fillers {}');
    buf.writeln('foreach sz {64 32 16 8 4} {');
    buf.writeln('    lappend fillers \${CELL_LIB}__fillcap_\$sz');
    buf.writeln('}');
    buf.writeln('foreach sz {64 32 16 8 4 2 1} {');
    buf.writeln('    lappend fillers \${CELL_LIB}__fill_\$sz');
    buf.writeln('}');
    buf.writeln('filler_placement \$fillers');
    buf.writeln();

    // Route. Tile signals stay between Metal2 and Metal4. Metal5 is
    // reserved for the top-level horizontal power straps so the tile
    // never collides with the top PDN inside its own footprint.
    buf.writeln('set_routing_layers -signal Metal2-Metal4');
    buf.writeln('# Apply per-layer routing capacity adjustments');
    buf.writeln('if {[array exists LAYER_ADJ]} {');
    buf.writeln('    foreach layer [array names LAYER_ADJ] {');
    buf.writeln(
      '        set_global_routing_layer_adjustment \$layer \$LAYER_ADJ(\$layer)',
    );
    buf.writeln('    }');
    buf.writeln('}');
    buf.writeln('global_route -allow_congestion');
    buf.writeln(
      'detailed_route -droute_end_iter 32 '
      '-output_drc \${DEVICE_NAME}_${tileModule}_drc.rpt',
    );
    buf.writeln();

    // Antenna check + repair via layer-bumping only. Reclassify any
    // ANTENNACELL master to plain CORE so repair_antennas will not
    // instantiate diode cells.
    buf.writeln('foreach lib [[ord::get_db] getLibs] {');
    buf.writeln('    foreach mast [\$lib getMasters] {');
    buf.writeln('        if {[\$mast getType] eq "CORE_ANTENNACELL"} {');
    buf.writeln('            \$mast setType "CORE"');
    buf.writeln('        }');
    buf.writeln('    }');
    buf.writeln('}');
    buf.writeln(
      'check_antennas -report_file '
      '${tileModule}_antenna_pre.rpt',
    );
    // repair_antennas does its own incremental routing; skip a follow-up
    // detailed_route to avoid pin-access conflicts (DRT-1231).
    buf.writeln('repair_antennas');
    buf.writeln('check_antennas -report_file ${tileModule}_antenna.rpt');
    buf.writeln();

    // Reports
    buf.writeln(
      'report_checks -path_delay min_max '
      '> ${tileModule}_timing.rpt',
    );
    buf.writeln('report_design_area > ${tileModule}_area.rpt');
    buf.writeln();

    // Write outputs
    buf.writeln('write_def \${DEVICE_NAME}_${tileModule}_final.def');
    buf.writeln('write_verilog \${DEVICE_NAME}_${tileModule}_final.v');
    buf.writeln();

    // Generate LEF abstract for top-level PnR
    buf.writeln('# Generate LEF abstract for use as a macro');
    buf.writeln('write_abstract_lef \${DEVICE_NAME}_${tileModule}.lef');
    buf.writeln();

    // Generate liberty timing model for top-level STA
    buf.writeln('# Generate liberty timing model for timing analysis');
    buf.writeln('write_timing_model \${DEVICE_NAME}_${tileModule}.lib');
    buf.writeln();

    return buf.toString();
  }

  void _writeLayerDetection(StringBuffer buf) {
    // Push pin exit layers up. Skip Metal1 (cell-internal) and the first
    // vertical layer (Metal2). Pins on Metal3/Metal4 keep top-level
    // inter-tile routing on the higher, less-congested layers.
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
  }
}
