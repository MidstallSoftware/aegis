import 'package:aegis_ip/aegis_ip.dart';
import 'package:args/args.dart';

ArgParser buildParser() {
  return ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addOption(
      'descriptor',
      abbr: 'd',
      help: 'Path to a device descriptor JSON file (from aegis-genip output).',
    )
    ..addFlag(
      'config-clk',
      abbr: 'c',
      help: 'Adds a clock domain for tile configuration',
    )
    ..addOption(
      'name',
      abbr: 'n',
      help: 'Device name (default: aegis_fpga)',
      defaultsTo: 'aegis_fpga',
    )
    ..addOption(
      'width',
      abbr: 'x',
      help: 'Number of tiles to have in the X axis',
    )
    ..addOption(
      'height',
      abbr: 'y',
      help: 'Number of tiles to have in the Y axis',
    )
    ..addOption(
      'tracks',
      abbr: 't',
      help: 'Width of the connections in the tiles',
    )
    ..addOption(
      'serdes',
      abbr: 's',
      help: 'Number of hard SerDes tiles (default: 4)',
    )
    ..addOption(
      'bram-interval',
      help: 'Place a BRAM column every N LUT columns (0 = no BRAM)',
    )
    ..addOption(
      'clock-tiles',
      help: 'Number of clock management tiles (default: 1)',
    )
    ..addOption('config-data-width', help: 'Width of the config data bus')
    ..addOption('config-address-width', help: 'Width of the config address bus')
    ..addOption(
      'cycles',
      help: 'Number of clock cycles to simulate (default: 100)',
      defaultsTo: '100',
    )
    ..addOption('vcd', help: 'Output VCD waveform file path')
    ..addOption(
      'bitstream',
      abbr: 'b',
      help: 'Path to bitstream file to load into config chain',
    );
}

void printUsage(ArgParser argParser) {
  print('Usage: aegis_sim [--descriptor <json>] [flags]');
  print('');
  print('Simulate an Aegis FPGA device. Configuration can come from:');
  print('  1. A descriptor JSON file (--descriptor / -d)');
  print('  2. Command-line arguments (-x, -y, -t, etc.)');
  print('');
  print('When using --descriptor, CLI args override descriptor values.');
  print('');
  print(argParser.usage);
}

Future<void> main(List<String> arguments) async {
  final ArgParser argParser = buildParser();
  try {
    final ArgResults results = argParser.parse(arguments);

    if (results.flag('help')) {
      printUsage(argParser);
      return;
    }

    final cycles = int.parse(results.option('cycles')!);
    final vcdPath = results.option('vcd');
    final bitstreamPath = results.option('bitstream');

    // Build the simulator from descriptor or CLI args
    final FpgaSimulator sim;
    final descriptorPath = results.option('descriptor');

    if (descriptorPath != null) {
      sim = await FpgaSimulator.fromDescriptor(
        descriptorPath,
        name: results.wasParsed('name') ? results.option('name') : null,
        width: results.wasParsed('width')
            ? int.parse(results.option('width')!)
            : null,
        height: results.wasParsed('height')
            ? int.parse(results.option('height')!)
            : null,
        tracks: results.wasParsed('tracks')
            ? int.parse(results.option('tracks')!)
            : null,
        serdesCount: results.wasParsed('serdes')
            ? int.parse(results.option('serdes')!)
            : null,
        bramColumnInterval: results.wasParsed('bram-interval')
            ? int.parse(results.option('bram-interval')!)
            : null,
        clockTileCount: results.wasParsed('clock-tiles')
            ? int.parse(results.option('clock-tiles')!)
            : null,
        configClk: results.wasParsed('config-clk')
            ? results.flag('config-clk')
            : null,
        configDataWidth: results.wasParsed('config-data-width')
            ? int.parse(results.option('config-data-width')!)
            : null,
        configAddressWidth: results.wasParsed('config-address-width')
            ? int.parse(results.option('config-address-width')!)
            : null,
      );
    } else {
      sim = await FpgaSimulator.create(
        name: results.option('name')!,
        width: int.parse(results.option('width') ?? '1'),
        height: int.parse(results.option('height') ?? '1'),
        tracks: int.parse(results.option('tracks') ?? '1'),
        serdesCount: int.parse(results.option('serdes') ?? '4'),
        bramColumnInterval: int.parse(results.option('bram-interval') ?? '0'),
        clockTileCount: int.parse(results.option('clock-tiles') ?? '1'),
        configClk: results.flag('config-clk'),
        configDataWidth: int.parse(results.option('config-data-width') ?? '8'),
        configAddressWidth: int.parse(
          results.option('config-address-width') ?? '8',
        ),
      );
    }

    final fpga = sim.fpga;
    print('Aegis FPGA Simulator');
    print('  Device: ${fpga.name}');
    print('  Fabric: ${fpga.width}x${fpga.height}');
    print('  Tracks: ${fpga.tracks}');
    print('  SerDes: ${fpga.serdesCount}');
    print('  BRAM interval: ${fpga.bramColumnInterval}');
    print('  Clock tiles: ${fpga.clockTileCount}');
    print('  Cycles: $cycles');
    if (bitstreamPath != null) {
      await sim.loadBitstream(bitstreamPath);
      print('  Bitstream: $bitstreamPath');
    }
    if (vcdPath != null) {
      sim.enableVcd(vcdPath);
      print('  VCD: $vcdPath');
    }
    print('');

    print('Simulating $cycles cycles...');
    await sim.run(cycles: cycles);

    print('');
    print('Simulation complete.');
    print('  configDone: ${fpga.configDone.value}');

    if (vcdPath != null) {
      print('  Waveform saved to: $vcdPath');
    }

    await sim.dispose();
  } on FormatException catch (e) {
    print(e.message);
    print('');
    printUsage(argParser);
  }
}
