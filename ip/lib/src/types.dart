/// Cardinal edge direction on the FPGA fabric.
enum Direction {
  north,
  east,
  south,
  west;

  /// The four edges in config-chain order (N, E, S, W).
  static const List<Direction> chainOrder = [north, east, south, west];
}

/// Pin mode for I/O mapping.
enum PinMode { input, output, inout }

/// Maps a named pin to a specific fabric edge position and track.
class PinMapping {
  final String name;
  final int x;
  final int y;
  final int track;
  final PinMode mode;
  final Direction axis;

  const PinMapping(
    this.name,
    this.x,
    this.y,
    this.axis, {
    this.track = 0,
    this.mode = PinMode.inout,
  });

  const PinMapping.input(this.name, this.x, this.y, this.axis, {this.track = 0})
    : mode = PinMode.input;

  const PinMapping.output(
    this.name,
    this.x,
    this.y,
    this.axis, {
    this.track = 0,
  }) : mode = PinMode.output;
}
