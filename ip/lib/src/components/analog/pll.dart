import '../../pdk/analog_block_info.dart';
import '../../pdk/pdk_provider.dart';
import 'sch_pin.dart';

/// Analog PLL block for tapeout - wraps/replaces the digital ClockTile.
///
/// Produces an xschem schematic that instantiates the PDK's PLL symbol
/// and exposes the same interface the digital FPGA expects.
class AnalogPll {
  final int index;
  final PdkProvider pdk;

  const AnalogPll({required this.index, required this.pdk});

  AnalogBlockInfo get blockInfo => pdk.pll(index: index);

  /// Canonical pin interface matching the digital ClockTile.
  static const pins = [
    SchPin(name: 'refClk', direction: SchPinDirection.input),
    SchPin(name: 'reset', direction: SchPinDirection.input),
    SchPin(name: 'clkOut', direction: SchPinDirection.output, width: 4),
    SchPin(name: 'locked', direction: SchPinDirection.output),
  ];

  /// Emit xschem .sch content for this PLL instance.
  String toSch() {
    final info = blockInfo;
    final buf = StringBuffer();
    buf.writeln('v {xschem version=3.4.6}');
    buf.writeln('G {}');
    buf.writeln('V {}');

    // Instance the PDK PLL symbol
    final props = <String>[
      'name=${info.properties['name'] ?? 'pll_$index'}',
      ...info.properties.entries
          .where((e) => e.key != 'name')
          .map((e) => '${e.key}=${e.value}'),
    ];
    buf.writeln('C {${info.symbolPath}} 0 0 0 0 {${props.join(' ')}}');

    // Pin stubs for connectivity
    for (final pin in pins) {
      final dir = pin.direction == SchPinDirection.input ? 'in' : 'out';
      final pdkName = info.pinMapping[pin.name] ?? pin.name;
      if (pin.isBus) {
        for (int i = 0; i < pin.width; i++) {
          final aegisName = '${pin.name}[$i]';
          final mappedName = info.pinMapping[aegisName] ?? '${pdkName}[$i]';
          buf.writeln('B 5 0 0 0 0 {name=$mappedName dir=$dir}');
        }
      } else {
        buf.writeln('B 5 0 0 0 0 {name=$pdkName dir=$dir}');
      }
    }

    return buf.toString();
  }
}
