/// Formats a sensor reading to two decimal places.
String formatValue(double value) => value.toStringAsFixed(2);

/// Formats an optional sensor reading, or an em dash if it isn't available.
String formatOptional(double? value, {int decimals = 2}) =>
    value != null ? value.toStringAsFixed(decimals) : "-";
