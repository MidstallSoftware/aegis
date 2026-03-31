import '../../pdk/analog_block_info.dart';
import '../../pdk/pdk_provider.dart';
import 'sch_pin.dart';

/// Analog I/O pad cell for tapeout - wraps/replaces the digital IOTile.
///
/// Produces an xschem schematic that instantiates the PDK's I/O cell symbol
/// and exposes the same interface the digital FPGA expects.
class AnalogIoCell {
  final int index;
  final PdkProvider pdk;

  const AnalogIoCell({required this.index, required this.pdk});

  AnalogBlockInfo get blockInfo => pdk.ioCell(index: index);

  /// Canonical pin interface matching the digital IOTile.
  static const pins = [
    SchPin(name: 'padIn', direction: SchPinDirection.input),
    SchPin(name: 'padOut', direction: SchPinDirection.output),
    SchPin(name: 'padOutputEnable', direction: SchPinDirection.input),
    SchPin(name: 'fabricIn', direction: SchPinDirection.input),
    SchPin(name: 'fabricOut', direction: SchPinDirection.output),
  ];

  /// Emit xschem .sch content for this I/O cell instance.
  String toSch() {
    final info = blockInfo;
    final buf = StringBuffer();
    buf.writeln('v {xschem version=3.4.6}');
    buf.writeln('G {}');
    buf.writeln('V {}');

    final props = <String>[
      'name=${info.properties['name'] ?? 'io_$index'}',
      ...info.properties.entries
          .where((e) => e.key != 'name')
          .map((e) => '${e.key}=${e.value}'),
    ];
    buf.writeln('C {${info.symbolPath}} 0 0 0 0 {${props.join(' ')}}');

    for (final pin in pins) {
      final dir = pin.direction == SchPinDirection.input ? 'in' : 'out';
      final pdkName = info.pinMapping[pin.name] ?? pin.name;
      buf.writeln('B 5 0 0 0 0 {name=$pdkName dir=$dir}');
    }

    return buf.toString();
  }
}
