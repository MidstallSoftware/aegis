import 'package:aegis_ip/aegis_ip.dart';
import 'package:test/test.dart';

void main() {
  group('PdkProvider', () {
    test('registry contains generic', () {
      expect(PdkProvider.registry, contains('generic'));
    });

    test('resolve returns generic for unknown name', () {
      final pdk = PdkProvider.resolve(
        'nonexistent',
        symbolBasePath: '/test/path',
      );
      expect(pdk, isA<GenericPdkProvider>());
    });

    test('resolve returns generic by name', () {
      final pdk = PdkProvider.resolve('generic', symbolBasePath: '/test/path');
      expect(pdk, isA<GenericPdkProvider>());
    });
  });

  group('GenericPdkProvider', () {
    final pdk = GenericPdkProvider(
      symbolBasePath: '/nix/store/test-genip/share/aegis-ip',
    );

    test('pll returns absolute symbol path', () {
      final info = pdk.pll(index: 0);
      expect(
        info.symbolPath,
        '/nix/store/test-genip/share/aegis-ip/aegis_pll.sym',
      );
      expect(info.pinMapping, contains('refClk'));
      expect(info.pinMapping, contains('locked'));
      expect(info.pinMapping, contains('clkOut[0]'));
      expect(info.properties['name'], 'pll_0');
    });

    test('serdes returns absolute symbol path', () {
      final info = pdk.serdes(index: 2);
      expect(
        info.symbolPath,
        '/nix/store/test-genip/share/aegis-ip/aegis_serdes.sym',
      );
      expect(info.pinMapping, contains('serialIn'));
      expect(info.pinMapping, contains('serialOut'));
      expect(info.properties['name'], 'serdes_2');
    });

    test('ioCell returns absolute symbol path', () {
      final info = pdk.ioCell(index: 5);
      expect(
        info.symbolPath,
        '/nix/store/test-genip/share/aegis-ip/aegis_io_cell.sym',
      );
      expect(info.pinMapping, contains('padIn'));
      expect(info.pinMapping, contains('padOut'));
      expect(info.pinMapping, contains('padOutputEnable'));
      expect(info.properties['name'], 'io_5');
    });
  });
}
