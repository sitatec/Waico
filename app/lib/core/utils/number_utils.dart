extension DoubleExtensions on double {
  /// Converts a double to a string, and removes the decimals if they are all zeros.
  String toStringWithoutZeroDecimal({int numDecimals = 2}) {
    final newVal = double.parse(toStringAsFixed(numDecimals));
    return (newVal % 1 == 0 ? newVal.toInt() : newVal).toString();
  }
}
