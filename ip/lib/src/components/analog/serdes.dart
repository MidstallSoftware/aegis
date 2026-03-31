import '../../pdk/analog_block_info.dart';
import '../../pdk/pdk_provider.dart';
import 'sch_pin.dart';

/// Analog hard SerDes block for tapeout - wraps/replaces the digital SerDesTile.
///
/// Produces an xschem schematic that instantiates the PDK's SerDes symbol
/// and exposes the same interface the digital FPGA expects.
class AnalogSerdes {
  final int index;
  final PdkProvider pdk;

  const AnalogSerdes({required this.index, required this.pdk});

  AnalogBlockInfo get blockInfo => pdk.serdes(index: index);

  /// Canonical pin interface matching the digital SerDesTile.
  static const pins = [
    SchPin(name: 'serialIn', direction: SchPinDirection.input),
    SchPin(name: 'serialOut', direction: SchPinDirection.output),
    SchPin(name: 'txReady', direction: SchPinDirection.output),
    SchPin(name: 'rxValid', direction: SchPinDirection.output),
    SchPin(name: 'fabricIn', direction: SchPinDirection.input),
    SchPin(name: 'fabricOut', direction: SchPinDirection.output),
  ];

  /// Emit xschem .sch content for this SerDes instance.
  String toSch() {
    final info = blockInfo;
    final buf = StringBuffer();
    buf.writeln('v {xschem version=3.4.6}');
    buf.writeln('G {}');
    buf.writeln('V {}');

    final props = <String>[
      'name=${info.properties['name'] ?? 'serdes_$index'}',
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
