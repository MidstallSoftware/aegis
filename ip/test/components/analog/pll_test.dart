import 'package:aegis_ip/aegis_ip.dart';
import 'package:test/test.dart';

void main() {
  group('AnalogPll', () {
    final pdk = GenericPdkProvider(symbolBasePath: '/test/symbols');

    test('has correct pin definitions', () {
      expect(AnalogPll.pins, hasLength(4));
      expect(
        AnalogPll.pins.map((p) => p.name),
        containsAll(['refClk', 'reset', 'clkOut', 'locked']),
      );
    });

    test('clkOut pin is a 4-wide bus', () {
      final clkOut = AnalogPll.pins.firstWhere((p) => p.name == 'clkOut');
      expect(clkOut.width, 4);
      expect(clkOut.isBus, isTrue);
    });

    test('toSch emits valid schematic', () {
      final pll = AnalogPll(index: 0, pdk: pdk);
      final sch = pll.toSch();
      expect(sch, contains('v {xschem version=3.4.6}'));
      expect(sch, contains('/test/symbols/aegis_pll.sym'));
      expect(sch, contains('name=pll_0'));
    });

    test('blockInfo uses PDK provider', () {
      final pll = AnalogPll(index: 1, pdk: pdk);
      expect(pll.blockInfo.symbolPath, '/test/symbols/aegis_pll.sym');
      expect(pll.blockInfo.properties['name'], 'pll_1');
    });
  });
}
