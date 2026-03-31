import '../components/analog/io_cell.dart';
import '../components/analog/pll.dart';
import '../components/analog/serdes.dart';
import '../pdk/pdk_provider.dart';

/// Emits an xschem TCL script that builds the top-level mixed-signal schematic.
///
/// The script can be sourced via `xschem --tcl <file>` to programmatically
/// construct the schematic, place analog blocks, and wire them to the
/// digital FPGA module.
class XschemTclEmitter {
  final String deviceName;
  final int clockTileCount;
  final int serdesCount;
  final int totalPads;
  final int width;
  final int height;
  final PdkProvider pdk;

  const XschemTclEmitter({
    required this.deviceName,
    required this.clockTileCount,
    required this.serdesCount,
    required this.totalPads,
    required this.width,
    required this.height,
    required this.pdk,
  });

  /// Grid spacing for xschem layout (in xschem units).
  static const int _gridSpacing = 200;

  /// Generates the complete TCL script.
  String generate() {
    final buf = StringBuffer();

    _writeHeader(buf);
    _placeFpga(buf);
    _placePlls(buf);
    _placeSerdes(buf);
    _placeIoCells(buf);
    _writeFooter(buf);

    return buf.toString();
  }

  void _writeHeader(StringBuffer buf) {
    buf.writeln('# Auto-generated xschem TCL script for $deviceName');
    buf.writeln('# PDK: ${pdk.name}');
    buf.writeln('#');
    buf.writeln('# Source this file in xschem:');
    buf.writeln('#   xschem --tcl $deviceName-xschem.tcl');
    buf.writeln();
    buf.writeln('xschem clear');
    buf.writeln();
  }

  void _placeFpga(StringBuffer buf) {
    final fpgaX = _gridSpacing * (totalPads ~/ 2 + 2);
    final fpgaY = _gridSpacing * (serdesCount + clockTileCount + 2);

    buf.writeln('# Digital FPGA fabric');
    buf.writeln(
      'xschem instance $deviceName.sym '
      '$fpgaX $fpgaY 0 0 '
      '{name=$deviceName type=subcircuit}',
    );
    buf.writeln();
  }

  void _placePlls(StringBuffer buf) {
    if (clockTileCount == 0) return;

    final fpgaX = _gridSpacing * (totalPads ~/ 2 + 2);
    final fpgaY = _gridSpacing * (serdesCount + clockTileCount + 2);

    buf.writeln('# PLL instances');
    for (int i = 0; i < clockTileCount; i++) {
      final pll = AnalogPll(index: i, pdk: pdk);
      final info = pll.blockInfo;
      final x = fpgaX - _gridSpacing * 4;
      final y = fpgaY - _gridSpacing * (clockTileCount - i);

      buf.writeln(
        'xschem instance ${_tclEscape(info.symbolPath)} '
        '$x $y 0 0 '
        '{${_formatProps(info.properties, 'pll_$i')}}',
      );

      // Wire refClk
      buf.writeln(
        'xschem wire '
        '{$x ${y - 20} ${fpgaX - 20} ${y - 20}}',
      );
    }
    buf.writeln();
  }

  void _placeSerdes(StringBuffer buf) {
    if (serdesCount == 0) return;

    final fpgaX = _gridSpacing * (totalPads ~/ 2 + 2);
    final fpgaY = _gridSpacing * (serdesCount + clockTileCount + 2);

    buf.writeln('# SerDes instances');
    for (int i = 0; i < serdesCount; i++) {
      final sd = AnalogSerdes(index: i, pdk: pdk);
      final info = sd.blockInfo;
      final x = fpgaX + _gridSpacing * 4;
      final y = fpgaY - _gridSpacing * (serdesCount - i);

      buf.writeln(
        'xschem instance ${_tclEscape(info.symbolPath)} '
        '$x $y 0 0 '
        '{${_formatProps(info.properties, 'serdes_$i')}}',
      );

      // Wire serialOut from FPGA to SerDes
      buf.writeln(
        'xschem wire '
        '{${fpgaX + 20} $y $x $y}',
      );
      // Wire serialIn from SerDes to external
      buf.writeln(
        'xschem wire '
        '{$x ${y + 20} ${x + _gridSpacing} ${y + 20}}',
      );
    }
    buf.writeln();
  }

  void _placeIoCells(StringBuffer buf) {
    if (totalPads == 0) return;

    final fpgaX = _gridSpacing * (totalPads ~/ 2 + 2);
    final fpgaY = _gridSpacing * (serdesCount + clockTileCount + 2);

    buf.writeln('# I/O cell instances');
    int padIndex = 0;

    // North edge
    for (int i = 0; i < width; i++) {
      final cell = AnalogIoCell(index: padIndex, pdk: pdk);
      final info = cell.blockInfo;
      final x = fpgaX - _gridSpacing * (width ~/ 2 - i);
      final y = fpgaY - _gridSpacing * 3;

      buf.writeln(
        'xschem instance ${_tclEscape(info.symbolPath)} '
        '$x $y 0 0 '
        '{${_formatProps(info.properties, 'io_$padIndex')}}',
      );
      padIndex++;
    }

    // East edge
    for (int i = 0; i < height; i++) {
      final cell = AnalogIoCell(index: padIndex, pdk: pdk);
      final info = cell.blockInfo;
      final x = fpgaX + _gridSpacing * 3;
      final y = fpgaY - _gridSpacing * (height ~/ 2 - i);

      buf.writeln(
        'xschem instance ${_tclEscape(info.symbolPath)} '
        '$x $y 0 0 '
        '{${_formatProps(info.properties, 'io_$padIndex')}}',
      );
      padIndex++;
    }

    // South edge
    for (int i = 0; i < width; i++) {
      final cell = AnalogIoCell(index: padIndex, pdk: pdk);
      final info = cell.blockInfo;
      final x = fpgaX + _gridSpacing * (width ~/ 2 - i);
      final y = fpgaY + _gridSpacing * 3;

      buf.writeln(
        'xschem instance ${_tclEscape(info.symbolPath)} '
        '$x $y 0 0 '
        '{${_formatProps(info.properties, 'io_$padIndex')}}',
      );
      padIndex++;
    }

    // West edge
    for (int i = 0; i < height; i++) {
      final cell = AnalogIoCell(index: padIndex, pdk: pdk);
      final info = cell.blockInfo;
      final x = fpgaX - _gridSpacing * 3;
      final y = fpgaY + _gridSpacing * (height ~/ 2 - i);

      buf.writeln(
        'xschem instance ${_tclEscape(info.symbolPath)} '
        '$x $y 0 0 '
        '{${_formatProps(info.properties, 'io_$padIndex')}}',
      );
      padIndex++;
    }
    buf.writeln();
  }

  void _writeFooter(StringBuffer buf) {
    buf.writeln('# Save schematic');
    buf.writeln('xschem saveas $deviceName-xschem.sch');
  }

  String _formatProps(Map<String, String> properties, String defaultName) {
    final props = <String>[
      'name=${properties['name'] ?? defaultName}',
      ...properties.entries
          .where((e) => e.key != 'name')
          .map((e) => '${e.key}=${e.value}'),
    ];
    return props.join(' ');
  }

  /// Escape a string for use in TCL.
  String _tclEscape(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll('{', '\\{')
        .replaceAll('}', '\\}')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]')
        .replaceAll('"', '\\"')
        .replaceAll('\$', '\\\$');
  }
}
