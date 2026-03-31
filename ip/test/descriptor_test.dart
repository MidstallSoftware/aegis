import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:aegis_ip/aegis_ip.dart';
import 'package:json_schema/json_schema.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import 'package:test/test.dart';

late JsonSchema _schema;

void _expectValid(Map<String, dynamic> descriptor) {
  final result = _schema.validate(descriptor);
  expect(result.isValid, true, reason: result.errors.join('\n'));
}

void main() {
  setUpAll(() async {
    final packageUri = Uri.parse('package:aegis_ip/aegis_ip.dart');
    final resolved = await Isolate.resolvePackageUri(packageUri);
    final projectRoot = File.fromUri(resolved!).parent.parent;
    final schemaFile = File('${projectRoot.path}/data/descriptor.schema.json');
    final schemaJson = jsonDecode(schemaFile.readAsStringSync());
    _schema = JsonSchema.create(schemaJson);
  });

  tearDown(() async {
    await Simulator.reset();
  });

  group('descriptor schema validation', () {
    test('minimal 2x2 device', () async {
      final fpga = AegisFPGA(
        Logic(),
        Logic(),
        width: 2,
        height: 2,
        tracks: 4,
        padIn: Logic(width: 8),
        serialIn: Logic(width: 4),
        configReadPort: DataPortInterface(8, 8),
      );
      await fpga.build();

      _expectValid(fpga.toJsonDescriptor());
    });

    test('device with custom name', () async {
      final fpga = AegisFPGA(
        Logic(),
        Logic(),
        name: 'my_custom_chip',
        width: 2,
        height: 2,
        tracks: 4,
        padIn: Logic(width: 8),
        serialIn: Logic(width: 4),
        configReadPort: DataPortInterface(8, 8),
      );
      await fpga.build();

      final desc = fpga.toJsonDescriptor();
      _expectValid(desc);
      expect(desc['device'], 'my_custom_chip');
    });

    test('device with BRAM columns', () async {
      final fpga = AegisFPGA(
        Logic(),
        Logic(),
        width: 8,
        height: 4,
        tracks: 16,
        bramColumnInterval: 4,
        padIn: Logic(width: 24),
        serialIn: Logic(width: 4),
        configReadPort: DataPortInterface(8, 8),
      );
      await fpga.build();

      final desc = fpga.toJsonDescriptor();
      _expectValid(desc);

      final bramCols = desc['fabric']['bram']['columns'] as List;
      expect(bramCols, isNotEmpty);

      final tiles = desc['tiles'] as List;
      final bramTiles = tiles.where((t) => t['type'] == 'bram').toList();
      expect(bramTiles, isNotEmpty);
    });

    test('device with multiple clock tiles', () async {
      final fpga = AegisFPGA(
        Logic(),
        Logic(),
        width: 2,
        height: 2,
        tracks: 4,
        clockTileCount: 3,
        padIn: Logic(width: 8),
        serialIn: Logic(width: 4),
        configReadPort: DataPortInterface(8, 8),
      );
      await fpga.build();

      final desc = fpga.toJsonDescriptor();
      _expectValid(desc);
      expect(desc['clock']['tile_count'], 3);
      expect(desc['clock']['total_outputs'], 12);
    });

    test('device with many serdes', () async {
      final fpga = AegisFPGA(
        Logic(),
        Logic(),
        width: 4,
        height: 4,
        tracks: 8,
        serdesCount: 8,
        padIn: Logic(width: 16),
        serialIn: Logic(width: 8),
        configReadPort: DataPortInterface(8, 8),
      );
      await fpga.build();

      final desc = fpga.toJsonDescriptor();
      _expectValid(desc);
      expect(desc['serdes']['count'], 8);
      expect((desc['serdes']['edge_assignment'] as List).length, 8);
    });

    test('config total_bits matches chain_order sum', () async {
      final fpga = AegisFPGA(
        Logic(),
        Logic(),
        width: 4,
        height: 4,
        tracks: 16,
        bramColumnInterval: 2,
        serdesCount: 6,
        clockTileCount: 2,
        padIn: Logic(width: 16),
        serialIn: Logic(width: 6),
        configReadPort: DataPortInterface(8, 8),
      );
      await fpga.build();

      final desc = fpga.toJsonDescriptor();
      _expectValid(desc);

      final config = desc['config'] as Map<String, dynamic>;
      final totalBits = config['total_bits'] as int;
      final chainOrder = config['chain_order'] as List;
      final chainSum = chainOrder.fold<int>(
        0,
        (sum, s) => sum + (s['total_bits'] as int),
      );
      expect(totalBits, chainSum);
    });

    test('tile offsets are contiguous', () async {
      final fpga = AegisFPGA(
        Logic(),
        Logic(),
        width: 6,
        height: 3,
        tracks: 16,
        bramColumnInterval: 3,
        padIn: Logic(width: 18),
        serialIn: Logic(width: 4),
        configReadPort: DataPortInterface(8, 8),
      );
      await fpga.build();

      final desc = fpga.toJsonDescriptor();
      _expectValid(desc);

      final tiles = desc['tiles'] as List;
      int expectedOffset = 0;
      for (final tile in tiles) {
        expect(tile['config_offset'], expectedOffset);
        expectedOffset += tile['config_width'] as int;
      }
    });

    test('io pad count matches total_pads', () async {
      final fpga = AegisFPGA(
        Logic(),
        Logic(),
        width: 5,
        height: 3,
        tracks: 4,
        padIn: Logic(width: 16),
        serialIn: Logic(width: 4),
        configReadPort: DataPortInterface(8, 8),
      );
      await fpga.build();

      final desc = fpga.toJsonDescriptor();
      _expectValid(desc);

      final io = desc['io'] as Map<String, dynamic>;
      expect((io['pads'] as List).length, io['total_pads']);
    });
  });
}
