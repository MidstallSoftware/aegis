import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import '../../config/tile_config.dart';
import '../../types.dart';
import 'bram_tile.dart';
import 'clock_tile.dart';
import 'dsp_basic_tile.dart';
import 'fabric.dart';
import 'fabric_config_loader.dart';
import 'io_fabric.dart';
import 'jtag_tap.dart';
import 'io_tile.dart';
import 'serdes_tile.dart';
import 'tile.dart';

class AegisFPGA extends Module {
  Logic get configDone => output('configDone');

  final int width;
  final int height;
  final int tracks;
  final int serdesCount;
  final int bramColumnInterval;
  final int bramDataWidth;
  final int bramAddrWidth;
  final int dspColumnInterval;
  final int clockTileCount;
  final bool enableJtag;

  /// Total I/O pads (2*width + 2*height).
  int get totalPads => 2 * width + 2 * height;

  AegisFPGA(
    Logic clk,
    Logic reset, {
    String name = 'aegis_fpga',
    required this.width,
    required this.height,
    required this.tracks,
    this.serdesCount = 4,
    this.bramColumnInterval = 0,
    this.bramDataWidth = 8,
    this.bramAddrWidth = 7,
    this.dspColumnInterval = 0,
    this.clockTileCount = 1,
    this.enableJtag = false,
    required Logic padIn,
    required Logic serialIn,
    Logic? configClk,
    required DataPortInterface configReadPort,
  }) : super(name: name) {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);

    final pads = totalPads;
    padIn = addInput('padIn', padIn, width: pads);
    addOutput('padOut', width: pads);
    addOutput('padOutputEnable', width: pads);

    if (serdesCount > 0) {
      serialIn = addInput('serialIn', serialIn, width: serdesCount);
      addOutput('serialOut', width: serdesCount);
      addOutput('txReady', width: serdesCount);
      addOutput('rxValid', width: serdesCount);
    }

    addOutput('clkOut', width: clockTileCount * ClockTile.numOutputs);
    addOutput('clkLocked', width: clockTileCount);

    if (configClk != null) {
      configClk = addInput('configClk', configClk);
    }

    // JTAG ports (optional)
    JtagTap? jtag;
    if (enableJtag) {
      final tck = addInput('tck', Logic());
      final tms = addInput('tms', Logic());
      final tdi = addInput('tdi', Logic());
      final trst = addInput('trst', Logic());
      addOutput('tdo');

      jtag = JtagTap(tck, tms, tdi, trst);
      output('tdo') <= jtag.tdo;
    }

    configReadPort = configReadPort.clone()
      ..connectIO(
        this,
        configReadPort,
        inputTags: {DataPortGroup.data},
        outputTags: {DataPortGroup.control},
        uniquify: (orig) => 'configRead_$orig',
      );

    addOutput('configDone');

    final totalBits =
        clockTileCount * ClockTile.CONFIG_WIDTH +
        LutFabric.configBitsFor(
          width: width,
          height: height,
          tracks: tracks,
          bramColumnInterval: bramColumnInterval,
          dspColumnInterval: dspColumnInterval,
        ) +
        IOFabric.peripheralConfigBits(width, height, serdesCount: serdesCount);

    final loader = FabricConfigLoader(
      configClk ?? clk,
      reset,
      totalBits,
      configReadPort,
    );

    // When JTAG is enabled, a mux selects which source drives the config
    // chain. The TAP's enableConfig output controls the switch.
    final cfgIn = Logic(name: 'cfgIn');
    final cfgLoad = Logic(name: 'cfgLoad');
    final cfgReset = Logic(name: 'cfgReset');

    if (jtag != null) {
      cfgIn <= mux(jtag.enableConfig, jtag.cfgIn, loader.cfgIn);
      cfgLoad <= mux(jtag.enableConfig, jtag.cfgLoad, loader.cfgLoad);
      cfgReset <= reset | (jtag.enableConfig & jtag.cfgReset);
      configDone <= loader.done;
    } else {
      cfgIn <= loader.cfgIn;
      cfgLoad <= loader.cfgLoad;
      cfgReset <= reset;
      configDone <= loader.done;
    }

    // Clock tiles - config chain: clock tiles -> IO fabric -> LUT fabric
    final clockTiles = <ClockTile>[];
    var cfgChainSig = cfgIn;

    for (int i = 0; i < clockTileCount; i++) {
      final tileCfgIn = Logic(name: 'clkCfgIn_$i');
      tileCfgIn <= cfgChainSig;

      final ct = ClockTile(clk, cfgReset, tileCfgIn, cfgLoad);
      clockTiles.add(ct);
      cfgChainSig = ct.cfgOut;
    }

    // Collect clock outputs
    output('clkOut') <=
        clockTiles
            .expand(
              (ct) => List.generate(ClockTile.numOutputs, (i) => ct.clkOut[i]),
            )
            .toList()
            .reversed
            .toList()
            .swizzle();

    output('clkLocked') <=
        clockTiles.map((ct) => ct.locked).toList().reversed.toList().swizzle();

    // IO fabric receives config chain after clock tiles
    final ioFabric = IOFabric(
      clk,
      cfgReset,
      width: width,
      height: height,
      tracks: tracks,
      serdesCount: serdesCount,
      bramColumnInterval: bramColumnInterval,
      bramDataWidth: bramDataWidth,
      bramAddrWidth: bramAddrWidth,
      dspColumnInterval: dspColumnInterval,
      cfgIn: cfgChainSig,
      cfgLoad: cfgLoad,
      padIn: padIn,
      serialIn: serialIn,
    );

    output('padOut') <= ioFabric.padOut;
    output('padOutputEnable') <= ioFabric.padOutputEnable;
    if (serdesCount > 0) {
      output('serialOut') <= ioFabric.serialOut!;
      output('txReady') <= ioFabric.txReady!;
      output('rxValid') <= ioFabric.rxValid!;
    }
  }

  /// Generates a JSON-serializable descriptor of the device, suitable for
  /// consumption by external PNR and bitstream tools.
  Map<String, dynamic> toJsonDescriptor() {
    final bramCols = LutFabric.bramColumnSet(
      width: width,
      bramColumnInterval: bramColumnInterval,
    ).toList()..sort();

    final dspCols = LutFabric.dspColumnSet(
      width: width,
      dspColumnInterval: dspColumnInterval,
      bramColumnInterval: bramColumnInterval,
    ).toList()..sort();

    final fabricBits = LutFabric.configBitsFor(
      width: width,
      height: height,
      tracks: tracks,
      bramColumnInterval: bramColumnInterval,
      dspColumnInterval: dspColumnInterval,
    );
    final ioBits = totalPads * IOTile.CONFIG_WIDTH;
    final serdesBits = serdesCount * SerDesTile.CONFIG_WIDTH;
    final clockBits = clockTileCount * ClockTile.CONFIG_WIDTH;
    final totalBits = clockBits + ioBits + serdesBits + fabricBits;

    final grid = LutFabric.tileGridDescriptor(
      width: width,
      height: height,
      tracks: tracks,
      bramColumnInterval: bramColumnInterval,
      dspColumnInterval: dspColumnInterval,
    );

    return {
      'device': name,
      'fabric': {
        'width': width,
        'height': height,
        'tracks': tracks,
        'tile_config_width': tileConfigWidth(tracks),
        'bram': BramTile.descriptor(
          dataWidth: bramDataWidth,
          addrWidth: bramAddrWidth,
          bramColumnInterval: bramColumnInterval,
          columns: bramCols,
        ),
        'dsp': DspBasicTile.descriptor(
          dspColumnInterval: dspColumnInterval,
          columns: dspCols,
        ),
        'carry_chain': {'direction': 'south_to_north', 'per_column': true},
      },
      'io': IOTile.descriptor(
        totalPads: totalPads,
        width: width,
        height: height,
      ),
      'serdes': SerDesTile.descriptor(count: serdesCount),
      'clock': ClockTile.descriptor(count: clockTileCount),
      if (enableJtag) 'jtag': JtagTap.descriptor(idcode: 0x00000001),
      'config': {
        'total_bits': totalBits,
        'chain_order': [
          {
            'section': 'clock_tiles',
            'count': clockTileCount,
            'bits_per_tile': ClockTile.CONFIG_WIDTH,
            'total_bits': clockBits,
          },
          {
            'section': 'io_tiles',
            'count': totalPads,
            'bits_per_tile': IOTile.CONFIG_WIDTH,
            'total_bits': ioBits,
          },
          {
            'section': 'serdes_tiles',
            'count': serdesCount,
            'bits_per_tile': SerDesTile.CONFIG_WIDTH,
            'total_bits': serdesBits,
          },
          {
            'section': 'fabric_tiles',
            'count': width * height,
            'total_bits': fabricBits,
          },
        ],
      },
      'tiles': grid['tiles'],
    };
  }
}
