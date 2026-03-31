/// Emits Yosys techmap files for mapping designs onto the Aegis FPGA fabric.
///
/// Generates:
///   - Cell library Verilog (blackbox definitions of Aegis primitives)
///   - Techmap rules (mapping Yosys generic cells to Aegis cells)
///   - Synthesis TCL script targeting the Aegis architecture
class YosysTechmapEmitter {
  final String deviceName;
  final int width;
  final int height;
  final int tracks;
  final int bramDataWidth;
  final int bramAddrWidth;
  final int bramColumnInterval;

  int get bramDepth => 1 << bramAddrWidth;
  int get totalLuts => width * height;

  const YosysTechmapEmitter({
    required this.deviceName,
    required this.width,
    required this.height,
    required this.tracks,
    this.bramDataWidth = 8,
    this.bramAddrWidth = 7,
    this.bramColumnInterval = 0,
  });

  /// Generate Verilog blackbox cell definitions for Aegis primitives.
  String generateCells() {
    final buf = StringBuffer();

    buf.writeln('// Aegis FPGA cell library for $deviceName');
    buf.writeln('// Auto-generated - do not edit');
    buf.writeln();

    _writeLut4Cell(buf);
    _writeDffCell(buf);
    _writeCarryCell(buf);
    if (bramColumnInterval > 0) {
      _writeBramCell(buf);
    }

    return buf.toString();
  }

  /// Generate Yosys techmap rules.
  String generateTechmap() {
    final buf = StringBuffer();

    buf.writeln('// Aegis FPGA techmap rules for $deviceName');
    buf.writeln('// Auto-generated - do not edit');
    buf.writeln();

    _writeLutMap(buf);
    _writeDffMap(buf);
    _writeCarryMap(buf);
    if (bramColumnInterval > 0) {
      _writeBramMap(buf);
    }

    return buf.toString();
  }

  /// Generate a Yosys BRAM rules file for `memory_bram -rules`.
  ///
  /// Returns null if no BRAM is configured.
  String? generateBramRules() {
    if (bramColumnInterval <= 0) return null;

    final buf = StringBuffer();

    buf.writeln('# Aegis FPGA BRAM rules for $deviceName');
    buf.writeln('# ${bramDepth}x$bramDataWidth dual-port block RAM');
    buf.writeln();
    buf.writeln('bram AEGIS_BRAM');
    buf.writeln('  init 0');
    buf.writeln('  abits $bramAddrWidth');
    buf.writeln('  dbits $bramDataWidth');
    buf.writeln('  groups 2');
    buf.writeln('  ports  1 1');
    buf.writeln('  wrmode 1 1');
    buf.writeln('  enable 1 1');
    buf.writeln('  transp 0 0');
    buf.writeln('  clocks 1 1');
    buf.writeln('  clkpol 1 1');
    buf.writeln('endbram');
    buf.writeln();
    buf.writeln('match AEGIS_BRAM');
    buf.writeln('  min efficiency 1');
    buf.writeln('  shuffle_enable A');
    buf.writeln('endmatch');
    buf.writeln();

    return buf.toString();
  }

  /// Generate a Yosys TCL synthesis script targeting Aegis.
  String generateSynthScript() {
    final buf = StringBuffer();

    buf.writeln('# Aegis FPGA synthesis script for $deviceName');
    buf.writeln('# Fabric: ${width}x$height, $tracks tracks');
    if (bramColumnInterval > 0) {
      buf.writeln(
        '# BRAM: ${bramDepth}x$bramDataWidth every '
        '$bramColumnInterval columns',
      );
    }
    buf.writeln('#');
    buf.writeln('# TCL variables (VERILOG_FILES, TOP_MODULE, CELLS_V,');
    buf.writeln(
      '#   TECHMAP_V, BRAM_RULES, DEVICE_NAME) must be set before sourcing.',
    );
    buf.writeln();

    // Read design
    buf.writeln('# Read design');
    buf.writeln('foreach f \$VERILOG_FILES {');
    buf.writeln('    yosys read_verilog \$f');
    buf.writeln('}');
    buf.writeln();

    // Read cell library
    buf.writeln('# Read Aegis cell library');
    buf.writeln('yosys read_verilog -lib \$CELLS_V');
    buf.writeln();

    // BRAM mapping (before synthesis flattens memories)
    if (bramColumnInterval > 0) {
      buf.writeln('# Map block RAMs');
      buf.writeln('yosys memory_bram -rules \$BRAM_RULES');
      buf.writeln();
    }

    // Synthesis - nextpnr-generic expects $lut and $_DFF_P_ cells
    buf.writeln('# Synthesize to generic cells');
    buf.writeln('yosys synth -top \$TOP_MODULE -flatten');
    buf.writeln('yosys abc -lut 4');
    buf.writeln('yosys dfflegalize -cell {\$_DFF_P_} 0');
    buf.writeln('yosys abc -lut 4');
    buf.writeln();

    // Clean up
    buf.writeln('# Clean up');
    buf.writeln('yosys opt_clean -purge');
    buf.writeln();

    // Output
    buf.writeln('# Write outputs');
    buf.writeln('yosys write_json \${DEVICE_NAME}_pnr.json');
    buf.writeln('yosys write_verilog \${DEVICE_NAME}_mapped.v');
    buf.writeln('yosys stat');
    buf.writeln();

    return buf.toString();
  }

  void _writeLut4Cell(StringBuffer buf) {
    buf.writeln('(* blackbox *)');
    buf.writeln('module AEGIS_LUT4 (');
    buf.writeln('    input  wire       in0,');
    buf.writeln('    input  wire       in1,');
    buf.writeln('    input  wire       in2,');
    buf.writeln('    input  wire       in3,');
    buf.writeln('    output wire       out');
    buf.writeln(');');
    buf.writeln('    parameter [15:0] INIT = 16\'h0000;');
    buf.writeln('endmodule');
    buf.writeln();
  }

  void _writeDffCell(StringBuffer buf) {
    buf.writeln('(* blackbox *)');
    buf.writeln('module AEGIS_DFF (');
    buf.writeln('    input  wire clk,');
    buf.writeln('    input  wire d,');
    buf.writeln('    output reg  q');
    buf.writeln(');');
    buf.writeln('    always @(posedge clk)');
    buf.writeln('        q <= d;');
    buf.writeln('endmodule');
    buf.writeln();
  }

  void _writeCarryCell(StringBuffer buf) {
    buf.writeln('(* blackbox *)');
    buf.writeln('module AEGIS_CARRY (');
    buf.writeln('    input  wire p,');
    buf.writeln('    input  wire g,');
    buf.writeln('    input  wire ci,');
    buf.writeln('    output wire co,');
    buf.writeln('    output wire sum');
    buf.writeln(');');
    buf.writeln('    assign co  = p ? ci : g;');
    buf.writeln('    assign sum = p ^ ci;');
    buf.writeln('endmodule');
    buf.writeln();
  }

  void _writeBramCell(StringBuffer buf) {
    buf.writeln('(* blackbox *)');
    buf.writeln('module AEGIS_BRAM (');
    buf.writeln('    input  wire                    clk,');
    buf.writeln('    // Port A');
    buf.writeln('    input  wire [${bramAddrWidth - 1}:0]  a_addr,');
    buf.writeln('    input  wire [${bramDataWidth - 1}:0]  a_wdata,');
    buf.writeln('    input  wire                    a_we,');
    buf.writeln('    output wire [${bramDataWidth - 1}:0]  a_rdata,');
    buf.writeln('    // Port B');
    buf.writeln('    input  wire [${bramAddrWidth - 1}:0]  b_addr,');
    buf.writeln('    input  wire [${bramDataWidth - 1}:0]  b_wdata,');
    buf.writeln('    input  wire                    b_we,');
    buf.writeln('    output wire [${bramDataWidth - 1}:0]  b_rdata');
    buf.writeln(');');
    buf.writeln('    parameter INIT = 0;');
    buf.writeln('endmodule');
    buf.writeln();
  }

  // ---- Techmap rules ----

  void _writeLutMap(StringBuffer buf) {
    buf.writeln('// Map Yosys LUT4 to AEGIS_LUT4');
    buf.writeln(
      'module \\'
      r'\$lut (A, Y);',
    );
    buf.writeln('    parameter WIDTH = 0;');
    buf.writeln('    parameter LUT = 0;');
    buf.writeln('    input  [WIDTH-1:0] A;');
    buf.writeln('    output Y;');
    buf.writeln();
    buf.writeln('    generate');
    buf.writeln('        if (WIDTH == 4) begin');
    buf.writeln(
      '            AEGIS_LUT4 #(.INIT(LUT[15:0])) _TECHMAP_REPLACE_ (',
    );
    buf.writeln('                .in0(A[0]), .in1(A[1]),');
    buf.writeln('                .in2(A[2]), .in3(A[3]),');
    buf.writeln('                .out(Y)');
    buf.writeln('            );');
    buf.writeln('        end else if (WIDTH < 4) begin');
    buf.writeln('            // Pad unused inputs to zero for smaller LUTs');
    buf.writeln('            wire [3:0] padded;');
    buf.writeln('            assign padded = {{(4-WIDTH){1\'b0}}, A};');
    buf.writeln(
      '            AEGIS_LUT4 #(.INIT(LUT[15:0])) '
      '_TECHMAP_REPLACE_ (',
    );
    buf.writeln('                .in0(padded[0]), .in1(padded[1]),');
    buf.writeln('                .in2(padded[2]), .in3(padded[3]),');
    buf.writeln('                .out(Y)');
    buf.writeln('            );');
    buf.writeln('        end else begin');
    buf.writeln('            wire _TECHMAP_FAIL_ = 1;');
    buf.writeln('        end');
    buf.writeln('    endgenerate');
    buf.writeln('endmodule');
    buf.writeln();
  }

  void _writeDffMap(StringBuffer buf) {
    buf.writeln('// Map positive-edge DFF to AEGIS_DFF');
    buf.writeln(
      'module \\'
      r'\$_DFF_P_ (C, D, Q);',
    );
    buf.writeln('    input  C, D;');
    buf.writeln('    output Q;');
    buf.writeln('    AEGIS_DFF _TECHMAP_REPLACE_ (');
    buf.writeln('        .clk(C), .d(D), .q(Q)');
    buf.writeln('    );');
    buf.writeln('endmodule');
    buf.writeln();
  }

  void _writeCarryMap(StringBuffer buf) {
    buf.writeln('// Carry chain available for arithmetic mapping');
    buf.writeln('// Usage: instantiate AEGIS_CARRY directly or via');
    buf.writeln('// Yosys alumacc pass with carry chain extraction.');
    buf.writeln();
  }

  void _writeBramMap(StringBuffer buf) {
    buf.writeln('// BRAM inference is handled by a separate .rules file');
    buf.writeln('// passed to memory_bram -rules in the synth script.');
    buf.writeln();
  }
}
