import 'analog_block_info.dart';
import 'pdk_provider.dart';

/// Fallback PDK provider using local Aegis symbols.
///
/// Pin names match the Aegis canonical names (identity mapping).
/// Symbol paths are resolved relative to [symbolBasePath].
class GenericPdkProvider extends PdkProvider {
  @override
  String get name => 'Generic (bundled Aegis symbols)';

  @override
  final String symbolBasePath;

  GenericPdkProvider({required this.symbolBasePath});

  String _resolve(String sym) => '$symbolBasePath/$sym';

  @override
  AnalogBlockInfo pll({required int index}) => AnalogBlockInfo(
    symbolPath: _resolve('aegis_pll.sym'),
    pinMapping: {
      'refClk': 'refClk',
      'reset': 'reset',
      'clkOut[0]': 'clkOut[0]',
      'clkOut[1]': 'clkOut[1]',
      'clkOut[2]': 'clkOut[2]',
      'clkOut[3]': 'clkOut[3]',
      'locked': 'locked',
    },
    properties: {'name': 'pll_$index'},
  );

  @override
  AnalogBlockInfo serdes({required int index}) => AnalogBlockInfo(
    symbolPath: _resolve('aegis_serdes.sym'),
    pinMapping: {
      'serialIn': 'serialIn',
      'serialOut': 'serialOut',
      'txReady': 'txReady',
      'rxValid': 'rxValid',
      'fabricIn': 'fabricIn',
      'fabricOut': 'fabricOut',
    },
    properties: {'name': 'serdes_$index'},
  );

  @override
  AnalogBlockInfo ioCell({required int index}) => AnalogBlockInfo(
    symbolPath: _resolve('aegis_io_cell.sym'),
    pinMapping: {
      'padIn': 'padIn',
      'padOut': 'padOut',
      'padOutputEnable': 'padOutputEnable',
      'fabricIn': 'fabricIn',
      'fabricOut': 'fabricOut',
    },
    properties: {'name': 'io_$index'},
  );
}
