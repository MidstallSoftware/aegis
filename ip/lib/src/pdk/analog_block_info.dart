/// Describes an analog block's xschem symbol and its pin name mapping.
class AnalogBlockInfo {
  /// xschem symbol path (e.g., 'aegis_pll.sym' or a PDK-specific path).
  final String symbolPath;

  /// Maps Aegis canonical pin names to PDK-specific pin names.
  ///
  /// Keys are Aegis names (e.g., 'refClk', 'clkOut[0]', 'locked').
  /// Values are the corresponding PDK pin names.
  final Map<String, String> pinMapping;

  /// Additional xschem instance properties as key=value pairs.
  final Map<String, String> properties;

  const AnalogBlockInfo({
    required this.symbolPath,
    required this.pinMapping,
    this.properties = const {},
  });
}
