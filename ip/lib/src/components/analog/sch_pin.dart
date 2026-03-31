/// Pin direction in an xschem symbol.
enum SchPinDirection { input, output, inout }

/// A pin on an analog block's xschem symbol.
class SchPin {
  /// Canonical Aegis pin name.
  final String name;

  final SchPinDirection direction;

  /// Bus width (1 for scalar pins).
  final int width;

  const SchPin({required this.name, required this.direction, this.width = 1});

  /// Whether this is a bus pin.
  bool get isBus => width > 1;
}
