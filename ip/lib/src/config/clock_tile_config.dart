/// Phase offset for a clock output.
enum ClockPhase {
  deg0(0),
  deg90(1),
  deg180(2),
  deg270(3);

  final int value;
  const ClockPhase(this.value);
}

/// Configuration for a single clock output channel.
class ClockOutputConfig {
  final bool enable;
  final int divider;
  final ClockPhase phase;
  final bool fiftyPercentDuty;

  const ClockOutputConfig({
    this.enable = false,
    this.divider = 1,
    this.phase = ClockPhase.deg0,
    this.fiftyPercentDuty = true,
  }) : assert(divider >= 1 && divider <= 256);

  @override
  String toString() =>
      'ClockOutput(en: $enable, div: $divider, '
      'phase: $phase, 50%: $fiftyPercentDuty)';
}

/// Configuration for the clock management tile.
///
/// Layout (49 bits):
///   [0]       global enable
///   [8:1]     output 0 divider - 1
///   [16:9]    output 1 divider - 1
///   [24:17]   output 2 divider - 1
///   [32:25]   output 3 divider - 1
///   [34:33]   output 0 phase
///   [36:35]   output 1 phase
///   [38:37]   output 2 phase
///   [40:39]   output 3 phase
///   [41]      output 0 enable
///   [42]      output 1 enable
///   [43]      output 2 enable
///   [44]      output 3 enable
///   [45]      output 0 50% duty
///   [46]      output 1 50% duty
///   [47]      output 2 50% duty
///   [48]      output 3 50% duty
class ClockTileConfig {
  final bool enable;
  final List<ClockOutputConfig> outputs;

  const ClockTileConfig({
    this.enable = false,
    this.outputs = const [
      ClockOutputConfig(),
      ClockOutputConfig(),
      ClockOutputConfig(),
      ClockOutputConfig(),
    ],
  });

  /// Single output at half the reference frequency.
  static const divBy2 = ClockTileConfig(
    enable: true,
    outputs: [
      ClockOutputConfig(enable: true, divider: 2, fiftyPercentDuty: true),
      ClockOutputConfig(),
      ClockOutputConfig(),
      ClockOutputConfig(),
    ],
  );

  /// Four outputs: /1, /2, /4, /8.
  static const quadDivider = ClockTileConfig(
    enable: true,
    outputs: [
      ClockOutputConfig(enable: true, divider: 1, fiftyPercentDuty: true),
      ClockOutputConfig(enable: true, divider: 2, fiftyPercentDuty: true),
      ClockOutputConfig(enable: true, divider: 4, fiftyPercentDuty: true),
      ClockOutputConfig(enable: true, divider: 8, fiftyPercentDuty: true),
    ],
  );

  static const int width = 49;

  BigInt encode() {
    var bits = BigInt.from(enable ? 1 : 0);
    for (int i = 0; i < 4; i++) {
      bits |= BigInt.from(outputs[i].divider - 1) << (1 + i * 8);
    }
    for (int i = 0; i < 4; i++) {
      bits |= BigInt.from(outputs[i].phase.value) << (33 + i * 2);
    }
    for (int i = 0; i < 4; i++) {
      bits |= BigInt.from(outputs[i].enable ? 1 : 0) << (41 + i);
    }
    for (int i = 0; i < 4; i++) {
      bits |= BigInt.from(outputs[i].fiftyPercentDuty ? 1 : 0) << (45 + i);
    }
    return bits;
  }

  static ClockTileConfig decode(BigInt bits) {
    int field(int offset, int w) =>
        ((bits >> offset) & BigInt.from((1 << w) - 1)).toInt();

    return ClockTileConfig(
      enable: field(0, 1) == 1,
      outputs: List.generate(
        4,
        (i) => ClockOutputConfig(
          divider: field(1 + i * 8, 8) + 1,
          phase: ClockPhase.values[field(33 + i * 2, 2)],
          enable: field(41 + i, 1) == 1,
          fiftyPercentDuty: field(45 + i, 1) == 1,
        ),
      ),
    );
  }

  @override
  String toString() => 'ClockTileConfig(en: $enable, outputs: $outputs)';
}
