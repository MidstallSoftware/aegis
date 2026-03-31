import 'package:aegis_ip/aegis_ip.dart';
import 'package:test/test.dart';

void main() {
  group('AnalogIoCell', () {
    final pdk = GenericPdkProvider(symbolBasePath: '/test/symbols');

    test('has correct pin definitions', () {
      expect(AnalogIoCell.pins, hasLength(5));
      expect(
        AnalogIoCell.pins.map((p) => p.name),
        containsAll([
          'padIn',
          'padOut',
          'padOutputEnable',
          'fabricIn',
          'fabricOut',
        ]),
      );
    });

    test('toSch emits valid schematic', () {
      final cell = AnalogIoCell(index: 0, pdk: pdk);
      final sch = cell.toSch();
      expect(sch, contains('v {xschem version=3.4.6}'));
      expect(sch, contains('/test/symbols/aegis_io_cell.sym'));
      expect(sch, contains('name=io_0'));
    });

    test('blockInfo uses PDK provider', () {
      final cell = AnalogIoCell(index: 7, pdk: pdk);
      expect(cell.blockInfo.symbolPath, '/test/symbols/aegis_io_cell.sym');
      expect(cell.blockInfo.properties['name'], 'io_7');
    });
  });
}
