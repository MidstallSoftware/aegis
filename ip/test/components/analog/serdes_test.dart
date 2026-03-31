import 'package:aegis_ip/aegis_ip.dart';
import 'package:test/test.dart';

void main() {
  group('AnalogSerdes', () {
    final pdk = GenericPdkProvider(symbolBasePath: '/test/symbols');

    test('has correct pin definitions', () {
      expect(AnalogSerdes.pins, hasLength(6));
      expect(
        AnalogSerdes.pins.map((p) => p.name),
        containsAll([
          'serialIn',
          'serialOut',
          'txReady',
          'rxValid',
          'fabricIn',
          'fabricOut',
        ]),
      );
    });

    test('toSch emits valid schematic', () {
      final sd = AnalogSerdes(index: 0, pdk: pdk);
      final sch = sd.toSch();
      expect(sch, contains('v {xschem version=3.4.6}'));
      expect(sch, contains('/test/symbols/aegis_serdes.sym'));
      expect(sch, contains('name=serdes_0'));
    });

    test('blockInfo uses PDK provider', () {
      final sd = AnalogSerdes(index: 3, pdk: pdk);
      expect(sd.blockInfo.symbolPath, '/test/symbols/aegis_serdes.sym');
      expect(sd.blockInfo.properties['name'], 'serdes_3');
    });
  });
}
