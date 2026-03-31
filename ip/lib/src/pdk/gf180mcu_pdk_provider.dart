import 'analog_block_info.dart';
import 'pdk_provider.dart';

/// GF180MCU PDK provider.
///
/// Maps Aegis analog blocks to GlobalFoundries 180nm xschem symbols.
/// Symbol paths use the PDK_ROOT convention for the GF180MCU PDK.
class Gf180mcuPdkProvider extends PdkProvider {
  @override
  String get name => 'GlobalFoundries GF180MCU 180nm';

  @override
  final String symbolBasePath;

  Gf180mcuPdkProvider({required this.symbolBasePath});

  String _resolve(String sym) => '$symbolBasePath/$sym';

  @override
  AnalogBlockInfo pll({required int index}) => AnalogBlockInfo(
    symbolPath: _resolve('gf180mcu_fd_pr__pll.sym'),
    pinMapping: {
      'refClk': 'CLK',
      'reset': 'RST',
      'clkOut[0]': 'CLKOUT0',
      'clkOut[1]': 'CLKOUT1',
      'clkOut[2]': 'CLKOUT2',
      'clkOut[3]': 'CLKOUT3',
      'locked': 'LOCK',
    },
    properties: {'name': 'pll_$index'},
  );

  @override
  AnalogBlockInfo serdes({required int index}) => AnalogBlockInfo(
    symbolPath: _resolve('gf180mcu_fd_pr__serdes.sym'),
    pinMapping: {
      'serialIn': 'RXD',
      'serialOut': 'TXD',
      'txReady': 'TX_RDY',
      'rxValid': 'RX_VLD',
      'fabricIn': 'DIN',
      'fabricOut': 'DOUT',
    },
    properties: {'name': 'serdes_$index'},
  );

  @override
  AnalogBlockInfo ioCell({required int index}) => AnalogBlockInfo(
    symbolPath: _resolve('gf180mcu_fd_io__bi_t.sym'),
    pinMapping: {
      'padIn': 'PAD',
      'padOut': 'A',
      'padOutputEnable': 'EN',
      'fabricIn': 'DIN',
      'fabricOut': 'DOUT',
    },
    properties: {'name': 'io_$index'},
  );
}
