import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';

import '../components/digital/fpga.dart';

/// Simulation wrapper for an Aegis FPGA device.
///
/// Can be configured from a device descriptor JSON or directly via
/// constructor parameters. Manages the ROHD simulation lifecycle
/// including bitstream loading through a [RegisterFile] connected
/// to the config read port.
class FpgaSimulator {
  final AegisFPGA fpga;
  final Logic clk;
  final Logic reset;
  final DataPortInterface configPort;
  final int configDataWidth;

  RegisterFile? _configMem;
  WaveDumper? _waveDumper;

  FpgaSimulator._({
    required this.fpga,
    required this.clk,
    required this.reset,
    required this.configPort,
    required this.configDataWidth,
  });

  /// Create a simulator from explicit parameters.
  static Future<FpgaSimulator> create({
    String name = 'aegis_fpga',
    required int width,
    required int height,
    required int tracks,
    int serdesCount = 4,
    int bramColumnInterval = 0,
    int clockTileCount = 1,
    bool configClk = false,
    int configDataWidth = 8,
    int configAddressWidth = 8,
    int clockPeriod = 10,
  }) async {
    final clk = SimpleClockGenerator(clockPeriod).clk;
    final reset = Logic(name: 'reset');
    final configPort = DataPortInterface(configDataWidth, configAddressWidth);

    final fpga = AegisFPGA(
      clk,
      reset,
      name: name,
      width: width,
      height: height,
      tracks: tracks,
      serdesCount: serdesCount,
      bramColumnInterval: bramColumnInterval,
      clockTileCount: clockTileCount,
      padIn: Logic(width: 2 * width + 2 * height),
      serialIn: Logic(width: serdesCount),
      configClk: configClk ? Logic() : null,
      configReadPort: configPort,
    );

    await fpga.build();
    return FpgaSimulator._(
      fpga: fpga,
      clk: clk,
      reset: reset,
      configPort: configPort,
      configDataWidth: configDataWidth,
    );
  }

  /// Create a simulator from a device descriptor JSON file.
  ///
  /// Individual parameters can be overridden via the optional arguments.
  static Future<FpgaSimulator> fromDescriptor(
    String path, {
    String? name,
    int? width,
    int? height,
    int? tracks,
    int? serdesCount,
    int? bramColumnInterval,
    int? clockTileCount,
    bool? configClk,
    int? configDataWidth,
    int? configAddressWidth,
    int clockPeriod = 10,
  }) async {
    final desc =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

    return create(
      name: name ?? (desc['device'] as String?) ?? 'aegis_fpga',
      width: width ?? (desc['fabric']?['width'] as int?) ?? 1,
      height: height ?? (desc['fabric']?['height'] as int?) ?? 1,
      tracks: tracks ?? (desc['fabric']?['tracks'] as int?) ?? 1,
      serdesCount: serdesCount ?? (desc['serdes']?['count'] as int?) ?? 4,
      bramColumnInterval:
          bramColumnInterval ??
          (desc['fabric']?['bram']?['column_interval'] as int?) ??
          0,
      clockTileCount:
          clockTileCount ?? (desc['clock']?['tile_count'] as int?) ?? 1,
      configClk: configClk ?? false,
      configDataWidth: configDataWidth ?? 8,
      configAddressWidth: configAddressWidth ?? 8,
      clockPeriod: clockPeriod,
    );
  }

  /// Load a bitstream file to be programmed into the config chain during
  /// simulation.
  ///
  /// Creates a [RegisterFile] pre-loaded with the bitstream data,
  /// connected to the FPGA's config read port. The [FabricConfigLoader]
  /// reads words from this memory and shifts them into the config chain
  /// after reset is deasserted.
  Future<void> loadBitstream(String path) async {
    await loadBitstreamBytes(File(path).readAsBytesSync());
  }

  /// Load a bitstream from raw bytes.
  Future<void> loadBitstreamBytes(Uint8List bytes) async {
    final bytesPerWord = configDataWidth ~/ 8;
    final numWords = (bytes.length + bytesPerWord - 1) ~/ bytesPerWord;

    // Build reset values map from bitstream bytes
    final resetValues = <int, int>{};
    for (int i = 0; i < numWords; i++) {
      int word = 0;
      for (int b = 0; b < bytesPerWord; b++) {
        final idx = i * bytesPerWord + b;
        if (idx < bytes.length) {
          word |= bytes[idx] << (b * 8);
        }
      }
      resetValues[i] = word;
    }

    _configMem = RegisterFile(
      clk,
      reset,
      [],
      [configPort],
      numEntries: numWords,
      resetValue: resetValues,
    );

    await _configMem!.build();
  }

  /// Enable VCD waveform dumping to [path].
  void enableVcd(String path) {
    _waveDumper = WaveDumper(fpga, outputPath: path);
  }

  /// Run the simulation for [cycles] clock cycles.
  ///
  /// Holds reset for [resetCycles] cycles at the start. If a bitstream
  /// is loaded, the config chain will be programmed after reset.
  Future<void> run({required int cycles, int resetCycles = 3}) async {
    // If no bitstream loaded, provide zero data on the config port
    if (_configMem == null) {
      configPort.data.inject(0);
    }

    reset.inject(1);
    Simulator.setMaxSimTime(cycles * 10 * 2);
    Simulator.registerAction(resetCycles * 10 * 2 + 10, () => reset.inject(0));

    await Simulator.run();
  }

  /// Clean up simulation state.
  Future<void> dispose() async {
    await Simulator.reset();
  }
}
