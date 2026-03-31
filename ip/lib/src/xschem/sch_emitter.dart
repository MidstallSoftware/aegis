import '../components/analog/io_cell.dart';
import '../components/analog/pll.dart';
import '../components/analog/serdes.dart';
import '../pdk/pdk_provider.dart';

/// Emits an xschem .sch file for the top-level mixed-signal design.
///
/// Places the digital FPGA module alongside analog PLL, SerDes, and I/O cell
/// instances, with wires connecting their ports.
class XschemSchEmitter {
  final String deviceName;
  final int clockTileCount;
  final int serdesCount;
  final int totalPads;
  final int width;
  final int height;
  final PdkProvider pdk;

  const XschemSchEmitter({
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

  /// Generates the complete .sch file content.
  String generate() {
    final buf = StringBuffer();

    // Header
    buf.writeln('v {xschem version=3.4.6}');
    buf.writeln('G {}');
    buf.writeln('V {}');
    buf.writeln('S {}');
    buf.writeln('E {}');

    // Place the digital FPGA module at center
    final fpgaX = _gridSpacing * (totalPads ~/ 2 + 2);
    final fpgaY = _gridSpacing * (serdesCount + clockTileCount + 2);
    buf.writeln(
      'C {$deviceName.sym} $fpgaX $fpgaY 0 0 '
      '{name=$deviceName type=subcircuit}',
    );

    // Place PLL instances to the left of the FPGA
    for (int i = 0; i < clockTileCount; i++) {
      final pll = AnalogPll(index: i, pdk: pdk);
      final info = pll.blockInfo;
      final x = fpgaX - _gridSpacing * 4;
      final y = fpgaY - _gridSpacing * (clockTileCount - i);
      buf.writeln(
        'C {${info.symbolPath}} $x $y 0 0 '
        '{${_formatProps(info.properties, 'pll_$i')}}',
      );

      // Wire PLL clkOut to FPGA clkOut
      final pllPins = info.pinMapping;
      final refClk = pllPins['refClk'] ?? 'refClk';
      buf.writeln(
        'N $x ${y - 20} ${fpgaX - 20} ${y - 20} '
        '{lab=$refClk}',
      );
    }

    // Place SerDes instances to the right of the FPGA
    for (int i = 0; i < serdesCount; i++) {
      final sd = AnalogSerdes(index: i, pdk: pdk);
      final info = sd.blockInfo;
      final x = fpgaX + _gridSpacing * 4;
      final y = fpgaY - _gridSpacing * (serdesCount - i);
      buf.writeln(
        'C {${info.symbolPath}} $x $y 0 0 '
        '{${_formatProps(info.properties, 'serdes_$i')}}',
      );

      // Wire SerDes serialIn/Out
      final serdesPins = info.pinMapping;
      final serialIn = serdesPins['serialIn'] ?? 'serialIn';
      final serialOut = serdesPins['serialOut'] ?? 'serialOut';
      buf.writeln(
        'N ${fpgaX + 20} $y $x $y '
        '{lab=${serialOut}_$i}',
      );
      buf.writeln(
        'N $x ${y + 20} ${x + _gridSpacing} ${y + 20} '
        '{lab=${serialIn}_$i}',
      );
    }

    // Place I/O cells around the perimeter
    _placeIoCells(buf, fpgaX, fpgaY);

    return buf.toString();
  }

  void _placeIoCells(StringBuffer buf, int fpgaX, int fpgaY) {
    int padIndex = 0;

    // North edge
    for (int i = 0; i < width; i++) {
      final cell = AnalogIoCell(index: padIndex, pdk: pdk);
      final info = cell.blockInfo;
      final x = fpgaX - _gridSpacing * (width ~/ 2 - i);
      final y = fpgaY - _gridSpacing * 3;
      buf.writeln(
        'C {${info.symbolPath}} $x $y 0 0 '
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
        'C {${info.symbolPath}} $x $y 0 0 '
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
        'C {${info.symbolPath}} $x $y 0 0 '
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
        'C {${info.symbolPath}} $x $y 0 0 '
        '{${_formatProps(info.properties, 'io_$padIndex')}}',
      );
      padIndex++;
    }
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
}
