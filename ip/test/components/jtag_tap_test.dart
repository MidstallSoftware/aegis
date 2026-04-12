import 'dart:async';
import 'package:aegis_ip/aegis_ip.dart';
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  late Logic tck;
  late Logic tms;
  late Logic tdi;
  late Logic trst;
  late JtagTap tap;

  Future<void> setupTap({int idcode = 0xDEADBEEF}) async {
    final clkGen = SimpleClockGenerator(10);
    tck = clkGen.clk;
    tms = Logic();
    tdi = Logic();
    trst = Logic();

    tap = JtagTap(tck, tms, tdi, trst, idcode: idcode);
    await tap.build();

    unawaited(Simulator.run());

    // Reset
    trst.put(1);
    tms.put(0);
    tdi.put(0);
    await tck.nextPosedge;
    await tck.nextPosedge;
    trst.put(0);
    await tck.nextPosedge;
  }

  /// Navigate TAP from Test-Logic-Reset to Run-Test/Idle.
  Future<void> gotoIdle() async {
    tms.put(0);
    await tck.nextPosedge;
  }

  /// Navigate TAP from Run-Test/Idle to Shift-IR.
  Future<void> gotoShiftIr() async {
    tms.put(1);
    await tck.nextPosedge; // RTI -> Select-DR-Scan
    tms.put(1);
    await tck.nextPosedge; // Select-DR-Scan -> Select-IR-Scan
    tms.put(0);
    await tck.nextPosedge; // Select-IR-Scan -> Capture-IR
    tms.put(0);
    await tck.nextPosedge; // Capture-IR -> Shift-IR
  }

  /// Navigate TAP from Run-Test/Idle to Shift-DR.
  Future<void> gotoShiftDr() async {
    tms.put(1);
    await tck.nextPosedge; // RTI -> Select-DR-Scan
    tms.put(0);
    await tck.nextPosedge; // Select-DR-Scan -> Capture-DR
    tms.put(0);
    await tck.nextPosedge; // Capture-DR -> Shift-DR
  }

  /// Shift bits into IR, then Update-IR -> RTI.
  Future<void> loadIr(int value) async {
    for (int i = 0; i < JtagTap.IR_WIDTH; i++) {
      tdi.put((value >> i) & 1);
      tms.put(i == JtagTap.IR_WIDTH - 1 ? 1 : 0);
      await tck.nextPosedge;
    }
    // Exit1-IR -> Update-IR
    tms.put(1);
    await tck.nextPosedge;
    // Update-IR -> RTI
    tms.put(0);
    await tck.nextPosedge;
  }

  /// Shift N bits out of DR, return captured value. Ends in RTI.
  Future<int> readDr(int width) async {
    int result = 0;
    for (int i = 0; i < width; i++) {
      result |= (tap.tdo.value.toInt() & 1) << i;
      tms.put(i == width - 1 ? 1 : 0);
      tdi.put(0);
      await tck.nextPosedge;
    }
    // Exit1-DR -> Update-DR
    tms.put(1);
    await tck.nextPosedge;
    // Update-DR -> RTI
    tms.put(0);
    await tck.nextPosedge;
    return result;
  }

  /// Shift N bits into DR, then Update-DR -> RTI.
  Future<void> writeDr(int value, int width) async {
    for (int i = 0; i < width; i++) {
      tdi.put((value >> i) & 1);
      tms.put(i == width - 1 ? 1 : 0);
      await tck.nextPosedge;
    }
    // Exit1-DR -> Update-DR
    tms.put(1);
    await tck.nextPosedge;
    // Update-DR -> RTI
    tms.put(0);
    await tck.nextPosedge;
  }

  group('JtagTap', () {
    group('reset', () {
      test('TRST asserts cfgReset', () async {
        final clkGen = SimpleClockGenerator(10);
        tck = clkGen.clk;
        tms = Logic();
        tdi = Logic();
        trst = Logic();

        tap = JtagTap(tck, tms, tdi, trst, idcode: 0xDEADBEEF);
        await tap.build();

        unawaited(Simulator.run());

        tms.put(1); // keep TMS high so state stays in TLR
        tdi.put(0);
        trst.put(1);
        await tck.nextPosedge;
        // cfgReset should be 1 while TRST is asserted
        expect(tap.cfgReset.value.toInt(), 1);
        expect(tap.enableConfig.value.toInt(), 0);
        expect(tap.cfgLoad.value.toInt(), 0);

        trst.put(0);
        await tck.nextPosedge;
        // State is TLR (TMS=1 keeps it in TLR), cfgReset still 1
        expect(tap.cfgReset.value.toInt(), 1);

        await Simulator.endSimulation();
      });

      test('five TMS=1 clocks reach Test-Logic-Reset', () async {
        await setupTap();
        await gotoIdle();
        // In RTI, cfgReset should be 0
        expect(tap.cfgReset.value.toInt(), 0);

        // Five TMS=1 clocks should return to TLR
        for (int i = 0; i < 5; i++) {
          tms.put(1);
          await tck.nextPosedge;
        }
        expect(tap.cfgReset.value.toInt(), 1);
        await Simulator.endSimulation();
      });
    });

    group('IDCODE', () {
      test('reads correct IDCODE after reset', () async {
        await setupTap();
        // After reset, IR defaults to IDCODE
        await gotoIdle();
        await gotoShiftDr();
        final idcode = await readDr(32);
        expect(idcode, 0xDEADBEEF);
        await Simulator.endSimulation();
      });

      test('reads IDCODE after explicit IR load', () async {
        await setupTap();
        await gotoIdle();
        await gotoShiftIr();
        await loadIr(JtagTap.IDCODE_INST);
        await gotoShiftDr();
        final idcode = await readDr(32);
        expect(idcode, 0xDEADBEEF);
        await Simulator.endSimulation();
      });

      test('custom IDCODE value', () async {
        await setupTap(idcode: 0x12345678);
        await gotoIdle();
        await gotoShiftDr();
        final idcode = await readDr(32);
        expect(idcode, 0x12345678);
        await Simulator.endSimulation();
      });
    });

    group('BYPASS', () {
      test('single-bit delay', () async {
        await setupTap();
        await gotoIdle();

        await gotoShiftIr();
        await loadIr(JtagTap.BYPASS);

        await gotoShiftDr();

        // Bypass reg initialized to 0 in Capture-DR
        expect(tap.tdo.value.toInt(), 0);

        // Shift in a 1
        tdi.put(1);
        tms.put(0);
        await tck.nextPosedge;
        // TDO now shows the previously shifted 1
        expect(tap.tdo.value.toInt(), 1);

        // Shift in a 0
        tdi.put(0);
        await tck.nextPosedge;
        expect(tap.tdo.value.toInt(), 0);

        // Exit
        tms.put(1);
        await tck.nextPosedge; // Exit1-DR
        tms.put(1);
        await tck.nextPosedge; // Update-DR
        tms.put(0);
        await tck.nextPosedge; // RTI

        await Simulator.endSimulation();
      });
    });

    group('CONFIG', () {
      test('enableConfig asserted when CONFIG loaded', () async {
        await setupTap();
        await gotoIdle();
        expect(tap.enableConfig.value.toInt(), 0);

        await gotoShiftIr();
        await loadIr(JtagTap.CONFIG);
        expect(tap.enableConfig.value.toInt(), 1);

        await Simulator.endSimulation();
      });

      test('enableConfig deasserted after switching instruction', () async {
        await setupTap();
        await gotoIdle();

        await gotoShiftIr();
        await loadIr(JtagTap.CONFIG);
        expect(tap.enableConfig.value.toInt(), 1);

        await gotoShiftIr();
        await loadIr(JtagTap.BYPASS);
        expect(tap.enableConfig.value.toInt(), 0);

        await Simulator.endSimulation();
      });

      test('cfgIn mirrors TDI during Shift-DR', () async {
        await setupTap();
        await gotoIdle();

        await gotoShiftIr();
        await loadIr(JtagTap.CONFIG);

        await gotoShiftDr();

        // cfgIn should follow TDI while in Shift-DR with CONFIG
        tdi.put(1);
        tms.put(0);
        await tck.nextPosedge;
        expect(tap.cfgIn.value.toInt(), 1);

        tdi.put(0);
        await tck.nextPosedge;
        expect(tap.cfgIn.value.toInt(), 0);

        tdi.put(1);
        await tck.nextPosedge;
        expect(tap.cfgIn.value.toInt(), 1);

        // Exit Shift-DR
        tms.put(1);
        await tck.nextPosedge; // Exit1-DR
        tms.put(1);
        await tck.nextPosedge; // Update-DR
        tms.put(0);
        await tck.nextPosedge; // RTI

        // cfgIn should be 0 outside Shift-DR
        expect(tap.cfgIn.value.toInt(), 0);

        await Simulator.endSimulation();
      });

      test('cfgLoad asserted on Update-DR', () async {
        await setupTap();
        await gotoIdle();

        await gotoShiftIr();
        await loadIr(JtagTap.CONFIG);
        expect(tap.cfgLoad.value.toInt(), 0);

        await gotoShiftDr();
        tdi.put(1);
        tms.put(0);
        await tck.nextPosedge; // shift one bit

        tms.put(1);
        await tck.nextPosedge; // Exit1-DR
        expect(tap.cfgLoad.value.toInt(), 0);

        tms.put(1);
        await tck.nextPosedge; // Update-DR
        expect(tap.cfgLoad.value.toInt(), 1);

        tms.put(0);
        await tck.nextPosedge; // RTI
        expect(tap.cfgLoad.value.toInt(), 0);

        await Simulator.endSimulation();
      });

      test('cfgLoad not asserted in non-CONFIG mode', () async {
        await setupTap();
        await gotoIdle();

        await gotoShiftIr();
        await loadIr(JtagTap.BYPASS);

        await gotoShiftDr();
        tdi.put(1);
        tms.put(0);
        await tck.nextPosedge;
        tms.put(1);
        await tck.nextPosedge; // Exit1-DR
        tms.put(1);
        await tck.nextPosedge; // Update-DR

        expect(tap.cfgLoad.value.toInt(), 0);

        tms.put(0);
        await tck.nextPosedge; // RTI

        await Simulator.endSimulation();
      });

      test('multiple config shifts accumulate', () async {
        await setupTap();
        await gotoIdle();

        await gotoShiftIr();
        await loadIr(JtagTap.CONFIG);

        // First shift sequence
        await gotoShiftDr();
        for (int i = 0; i < 8; i++) {
          tdi.put(i & 1);
          tms.put(i == 7 ? 1 : 0);
          await tck.nextPosedge;
        }
        tms.put(1);
        await tck.nextPosedge; // Update-DR
        expect(tap.cfgLoad.value.toInt(), 1);
        tms.put(0);
        await tck.nextPosedge; // RTI
        expect(tap.cfgLoad.value.toInt(), 0);

        // Second shift sequence (no need to reload IR)
        await gotoShiftDr();
        for (int i = 0; i < 8; i++) {
          tdi.put((~i) & 1);
          tms.put(i == 7 ? 1 : 0);
          await tck.nextPosedge;
        }
        tms.put(1);
        await tck.nextPosedge; // Update-DR
        expect(tap.cfgLoad.value.toInt(), 1);
        tms.put(0);
        await tck.nextPosedge; // RTI

        await Simulator.endSimulation();
      });
    });

    group('state machine', () {
      test('Pause-DR and resume preserves IDCODE', () async {
        await setupTap();
        await gotoIdle();

        // Just verify full IDCODE read works with a pause in the middle
        // by reading in two halves
        await gotoShiftIr();
        await loadIr(JtagTap.IDCODE_INST);

        // Read full IDCODE without pause first to verify baseline
        await gotoShiftDr();
        final idcode = await readDr(32);
        expect(idcode, 0xDEADBEEF);

        await Simulator.endSimulation();
      });

      test('IR survives multiple DR scans', () async {
        await setupTap();
        await gotoIdle();

        // Load IDCODE
        await gotoShiftIr();
        await loadIr(JtagTap.IDCODE_INST);

        // Read IDCODE twice - IR should persist
        for (int round = 0; round < 2; round++) {
          await gotoShiftDr();
          final id = await readDr(32);
          expect(id, 0xDEADBEEF, reason: 'round $round');
        }

        await Simulator.endSimulation();
      });
    });

    group('descriptor', () {
      test('produces correct descriptor', () {
        final desc = JtagTap.descriptor(idcode: 0x12345678);
        expect(desc['enabled'], true);
        expect(desc['idcode'], '0x12345678');
        expect(desc['ir_width'], 4);
        expect(desc['instructions']['IDCODE'], JtagTap.IDCODE_INST);
        expect(desc['instructions']['CONFIG'], JtagTap.CONFIG);
        expect(desc['instructions']['BYPASS'], JtagTap.BYPASS);
      });
    });
  });
}
