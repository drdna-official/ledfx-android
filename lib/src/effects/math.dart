import 'dart:typed_data';

/// Simple exponential smoothing filter with separate rise and decay factors.
///
/// This filter is designed to smooth a numeric stream, applying a faster
/// smoothing factor (alpha_rise) when the new value is increasing, and a
/// slower factor (alpha_decay) when the new value is decreasing.
class ExpFilter {
  // Constants for the smoothing factors
  final double alphaDecay;
  final double alphaRise;

  // The smoothed value (can hold a single number or a list/typed array)
  dynamic value;

  /// Constructor for ExpFilter.
  ///
  /// Throws an [ArgumentError] if the smoothing factors are out of the
  /// valid range (0.0 to 1.0, non-inclusive).
  ExpFilter({dynamic val, this.alphaDecay = 0.5, this.alphaRise = 0.5}) {
    if (alphaDecay <= 0.0 || alphaDecay >= 1.0) {
      throw ArgumentError(
        "Invalid decay smoothing factor: must be between 0.0 and 1.0 (exclusive)",
      );
    }
    if (alphaRise <= 0.0 || alphaRise >= 1.0) {
      throw ArgumentError(
        "Invalid rise smoothing factor: must be between 0.0 and 1.0 (exclusive)",
      );
    }
    value = val;
  }

  /// Updates the smoothed value with a new reading.
  ///
  /// The [value] parameter can be a single [double] or a [List<double>] (or a typed array).
  ///
  /// Returns the newly smoothed value.
  dynamic update(dynamic newValue) {
    // 1. Handle deferred initialization (if self.value is None)
    if (value == null) {
      value = newValue;
      return value;
    }

    // 2. Handle array/list update
    if (value is List<double> || value is Float64List || value is Float64List) {
      // Dart requires converting to a typed list for efficient element-wise operation
      final List<double> currentValueList = List<double>.from(value);
      final List<double> newValueList = List<double>.from(newValue);

      // Ensure lengths match to prevent errors
      if (currentValueList.length != newValueList.length) {
        throw ArgumentError(
          "New value list must match the size of the current value list.",
        );
      }

      final List<double> alphaList = [];

      for (int i = 0; i < currentValueList.length; i++) {
        // Calculate element-wise alpha
        if (newValueList[i] > currentValueList[i]) {
          alphaList.add(alphaRise); // rise smoothing
        } else {
          alphaList.add(alphaDecay); // decay smoothing
        }
      }

      // Perform element-wise exponential smoothing (value = alpha * value + (1.0 - alpha) * self.value)
      final List<double> smoothedList = List.generate(currentValueList.length, (
        i,
      ) {
        final double alpha = alphaList[i];
        final double current = currentValueList[i];
        final double new_ = newValueList[i];
        return alpha * new_ + (1.0 - alpha) * current;
      });

      // Update the internal value with the same type it started with
      if (value is Float64List) {
        value = Float64List.fromList(smoothedList);
      } else if (value is Float64List) {
        value = Float64List.fromList(smoothedList);
      } else {
        value = smoothedList;
      }

      return value;
    }
    // 3. Handle single number update (equivalent to the 'else' block)
    else if (value is num && newValue is num) {
      final double alpha;
      if (newValue > value) {
        alpha = alphaRise;
      } else {
        alpha = alphaDecay;
      }

      // Exponential smoothing formula
      value = alpha * newValue.toDouble() + (1.0 - alpha) * value.toDouble();
      return value;
    }

    // Handle unsupported type combinations
    throw ArgumentError(
      "Unsupported types for update: Current value is ${value.runtimeType}, New value is ${newValue.runtimeType}",
    );
  }
}
