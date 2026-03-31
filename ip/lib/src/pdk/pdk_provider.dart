import 'analog_block_info.dart';
import 'generic_pdk_provider.dart';
import 'gf180mcu_pdk_provider.dart';

/// Abstract interface for PDK-specific analog block definitions.
///
/// Each PDK provides symbol paths and pin mappings for the analog blocks
/// that surround the digital FPGA fabric: PLLs, hard SerDes transceivers,
/// and I/O pad cells.
abstract class PdkProvider {
  /// Human-readable PDK name.
  String get name;

  /// Base path where this PDK's xschem symbols are located.
  String get symbolBasePath;

  /// Returns the PLL symbol descriptor for clock tile [index].
  AnalogBlockInfo pll({required int index});

  /// Returns the hard SerDes symbol descriptor for channel [index].
  AnalogBlockInfo serdes({required int index});

  /// Returns the I/O pad cell symbol descriptor for pad [index].
  AnalogBlockInfo ioCell({required int index});

  /// Registry of known PDK provider factories, keyed by CLI name.
  ///
  /// Each factory takes a [symbolBasePath] and returns a configured provider.
  static final Map<String, PdkProvider Function(String symbolBasePath)>
  registry = {
    'generic': (path) => GenericPdkProvider(symbolBasePath: path),
    'gf180mcu': (path) => Gf180mcuPdkProvider(symbolBasePath: path),
  };

  /// Human-readable descriptions for the help output.
  static final Map<String, String> registryHelp = {
    'generic': 'Generic (bundled Aegis symbols)',
    'gf180mcu': 'GlobalFoundries GF180MCU 180nm',
  };

  /// Look up a provider by CLI name, falling back to generic.
  static PdkProvider resolve(String name, {required String symbolBasePath}) =>
      (registry[name] ?? registry['generic']!)(symbolBasePath);
}
