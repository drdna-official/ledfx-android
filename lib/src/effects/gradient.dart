import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:ledfx/src/effects/effect.dart';
import 'package:ledfx/src/effects/utils.dart';

class RgbColor {
  final double r, g, b;
  RgbColor(this.r, this.g, this.b);

  @override
  String toString() => 'RGB($r, $g, $b)';
}

// Equivalent to Python's Gradient class
class GradientDef {
  // List of (Color, Position) tuples
  final List<(RgbColor, double)> colors;
  GradientDef(this.colors);
}

mixin GradientAudioEffect on Effect {
  dynamic get gradient => GradientDef([
    (RgbColor(255, 0, 0), 0),
    (RgbColor(255, 120, 0), 14),
    (RgbColor(255, 200, 0), 28),
    (RgbColor(0, 255, 0), 42),
    (RgbColor(0, 199, 140), 56),
    (RgbColor(0, 0, 255), 70),
    (RgbColor(128, 0, 128), 84),
    (RgbColor(255, 0, 178), 98),
  ]);
  double get gradientRoll => 0.0;
  // 3xgradientLength -- rows -- r, g, b
  List<List<double>>? _gradientCurve;
  double _gradientRollCounter = 0.0;

  int get gradientPixelCount => () {
    return max(pixelCount, 256);
  }();

  List<Float64List> applyGradient(List<double> y) {
    assertGradient();

    // output = self.get_gradient() * y
    List<List<double>> gradient = getGradient();

    // N is the length of the intensity array (and gradient columns)
    final int N = y.length;

    // 1. Element-wise multiplication (Gradient (3 x N) * Intensity (1 x N))
    // We multiply each of the 3 gradient rows by the 1D intensity vector 'y'.
    List<List<double>> output = List.generate(3, (i) {
      final List<double> channel = gradient[i];
      final List<double> multipliedChannel = List<double>.filled(N, 0);

      for (int j = 0; j < N; j++) {
        // Multiplied element = Gradient_color[i, j] * Intensity[j]
        multipliedChannel[j] = channel[j] * y[j];
      }
      return multipliedChannel;
    });

    // 2. Apply and roll the gradient if necessary
    // self.roll_gradient()
    rollGradient();

    // 3. Return Transposed array: return output.T
    // The result is N x 3 (N rows for pixels, 3 columns for R, G, B).
    // Our current `output` is 3 x N. We need to transpose it.

    List<List<double>> transposedOutput = transpose3xNToNx3(output);

    // Transposition: output[i, j] becomes transposedOutput[j, i]
    // for (int i = 0; i < 3; i++) {
    //   // i is the channel (R, G, B)
    //   for (int j = 0; j < N; j++) {
    //     // j is the pixel index
    //     transposedOutput[j][i] = output[i][j];
    //   }
    // }

    final t = transposedOutput.map((e) => Float64List.fromList(e)).toList();
    return t;
  }

  void assertGradient() {
    if (_gradientCurve ==
            null // uninitialised gradient
            ||
        (_gradientCurve != null &&
            _gradientCurve![0].length != gradientPixelCount) // incorrect size
        ) {
      generateGradientCurve(gradient, gradientPixelCount);
    }
  }

  generateGradientCurve(dynamic gradient, int gradientLength) {
    debugPrint("generating new gradient curve");

    // --- CASE 1: Single Color (Python: if isinstance(gradient, RGB)) ---
    if (gradient is RgbColor) {
      // Python: np.tile(gradient, (gradient_length, 1)).astype(float).T
      // Creates a 3 x N array where every column is the color.
      _gradientCurve = List.filled(3, List.filled(gradientLength, 0));
      for (int i = 0; i < gradientLength; i++) {
        // Tiling RGB values into the flat array (Tiling logic for column-major access)
        _gradientCurve![0][i] = gradient.r;
        _gradientCurve![1][i] = gradient.g;
        _gradientCurve![2][i] = gradient.b;
      }
      return;
    }

    // --- CASE 2: Defined Gradient ---
    GradientDef gradientDef = gradient as GradientDef;
    List<(RgbColor, double)> gradientColors = List.of(
      gradientDef.colors,
    ).map((c) => (c.$1, c.$2 / 100)).toList();

    // 1. Fill in start and end colors if not explicitly given
    if (gradientColors.isNotEmpty && gradientColors.first.$2 != 0.0) {
      // Insert first color at position 0.0
      gradientColors.insert(0, (gradientColors.first.$1, 0.0));
    }

    // if gradient_colors[-1][1] != 1.0: ...
    if (gradientColors.last.$2 != 1.0) {
      // Insert last color at position 1.0
      gradientColors.add((gradientColors.last.$1, 1.0));
    }

    // 2. Split colors and splits (positions)
    // Python: gradient_colors, gradient_splits = zip(*gradient_colors)
    List<RgbColor> colors = gradientColors.map((e) => e.$1).toList();
    List<double> splits = gradientColors.map((e) => e.$2).toList();

    // 3. Convert splits (positions) into final array indexes
    // Python: gradient_splits = [int(gradient_length * position) for position in gradient_splits if 0 < position < 1]
    List<int> gradientSplits = splits
        .where((pos) => pos > 0.0 && pos < 1.0)
        .map(
          (pos) => (gradientLength * pos).round(),
        ) // Use round for better precision
        .toList();

    // 4. Pair colors for transition (1,2), (2,3), ...
    List<({RgbColor c1, RgbColor c2})> colorPairs = [];
    for (int i = 0; i < colors.length - 1; i++) {
      colorPairs.add((c1: colors[i], c2: colors[i + 1]));
    }

    // 5. Create the final gradient curve array
    // Python: gradient = np.zeros((gradient_length, 3)).astype(float)
    // We'll build the final array as a flat List<double> that's easy to access.
    List<List<double>> finalGradient = [[], [], []];

    // List<List<double>> finalGradient = List.filled(
    //   3,
    //   List.filled(gradientLength, 0),
    // );

    // Get the length of each segment
    List<int> segmentLengths = [];
    int currentSplit = 0;
    for (int splitIndex in gradientSplits) {
      segmentLengths.add(splitIndex - currentSplit);
      currentSplit = splitIndex;
    }
    // Add the length of the final segment (from the last split index to the end)
    segmentLengths.add(gradientLength - currentSplit);

    // 6. Fill segments using the ease function
    int segmentIndex = 0;
    for (var pair in colorPairs) {
      int segmentLen = segmentLengths[segmentIndex];

      // Calculate eased curves for R, G, B channels
      List<double> rCurve = _ease(segmentLen, pair.c1.r, pair.c2.r);
      List<double> gCurve = _ease(segmentLen, pair.c1.g, pair.c2.g);
      List<double> bCurve = _ease(segmentLen, pair.c1.b, pair.c2.b);

      // Combine R, G, B curves into the final flat gradient array
      for (int i = 0; i < segmentLen; i++) {
        finalGradient[0].add(rCurve[i]);
        finalGradient[1].add(gCurve[i]);
        finalGradient[2].add(bCurve[i]);
        // finalGradient[0][i] = rCurve[i];
        // finalGradient[1][i] = gCurve[i];
        // finalGradient[2][i] = bCurve[i];
      }
      segmentIndex++;
    }

    // The result is a flat [R, G, B, R, G, B, ...] array.
    // If you need the Python result (3 x N), you would structure this differently.
    // For general Dart/Flutter use, a flat list is often preferred.
    _gradientCurve = finalGradient;
    // Python: self._gradient_curve = gradient.T (Transposed)
    // The Python result is (3, N) - 3 rows (R, G, B) of N length each.
    // To match that exactly, we'd need to restructure the final List<double> into a 3xN structure.
  }

  List<double> _ease(
    int chunkLen,
    double startVal,
    double endVal, {
    double slope = 1.5,
  }) {
    if (chunkLen <= 0) {
      return [];
    }

    // 1. x = np.linspace(0, 1, chunk_len)
    List<double> x = linspace(0.0, 1.0, chunkLen);

    // 2. diff = end_val - start_val
    final double diff = endVal - startVal;

    // The main equation: diff * pow_x / (pow_x + np.power(1 - x, slope)) + start_val

    List<double> easedCurve = List<double>.filled(chunkLen, 0);

    for (int i = 0; i < chunkLen; i++) {
      double currentX = x[i];

      // Calculate components of the formula element-wise:

      // pow_x = np.power(x, slope)
      final double powX = pow(currentX, slope).toDouble();

      // np.power(1 - x, slope)
      final double powOneMinusX = pow(1.0 - currentX, slope).toDouble();

      // Full calculation:
      double easedValue;
      if (powX + powOneMinusX == 0.0) {
        // Avoid division by zero, though unlikely with this formula structure.
        easedValue = startVal;
      } else {
        easedValue = diff * (powX / (powX + powOneMinusX)) + startVal;
      }

      easedCurve[i] = easedValue;
    }

    return easedCurve;
  }

  List<List<double>> getGradient() {
    assertGradient();
    if (pixelCount == 1) return getGradientColors([0]);
    if (pixelCount < gradientPixelCount) {
      List<double> points = List<double>.generate(pixelCount, (i) {
        return i.toDouble() / (pixelCount - 1).toDouble();
      });
      return getGradientColors(points);
    }

    return _gradientCurve!;
  }

  List<List<double>> getGradientColors(List<double> points) {
    assertGradient();
    // The dimensions of the result will be 3 rows (R, G, B) and M columns (M = points.length)
    final int numPoints = points.length;

    // --- 1. Clamping  ---
    List<double> clampedPoints = points.map((p) => p.clamp(0.0, 1.0)).toList();

    // --- 2. Calculate Indices ---
    final int maxIndex = gradientPixelCount - 1;

    List<int> indices = clampedPoints
        .map((p) => (maxIndex * p).round())
        .toList();

    // --- 3. Advanced Indexing (Python: return self._gradient_curve[:, indices]) ---

    // Create the final result array (3 rows, numPoints columns)
    List<List<double>> resultColors = [
      List<double>.filled(numPoints, 0), // Red channel results
      List<double>.filled(numPoints, 0), // Green channel results
      List<double>.filled(numPoints, 0), // Blue channel results
    ];

    // Iterate through the target indices and pull the corresponding column data
    for (int i = 0; i < numPoints; i++) {
      int curveIndex = indices[i];

      // Select the R, G, B components at the calculated curveIndex
      resultColors[0][i] = _gradientCurve![0][curveIndex]; // Red
      resultColors[1][i] = _gradientCurve![1][curveIndex]; // Green
      resultColors[2][i] = _gradientCurve![2][curveIndex]; // Blue
    }

    // The result is a 3 x M array, matching the Python output structure.
    return resultColors;
  }

  void rollGradient() {
    if (gradientRoll == 0.0) {
      return;
    }
    assertGradient();

    final double increment = gradientRoll / pixelCount * gradientPixelCount;
    _gradientRollCounter += increment;

    if (_gradientRollCounter.abs() >= 1.0) {
      double pixelsToRollDouble = _gradientRollCounter.truncateToDouble();
      int pixelsToRoll = pixelsToRollDouble.toInt();

      _gradientRollCounter -= pixelsToRollDouble;
      final int offset = pixelsToRoll;

      // Apply the roll to R, G, and B channels in-place (by assigning the new list)
      _gradientCurve![0] = _rollChannel(_gradientCurve![0], offset); // Red
      _gradientCurve![1] = _rollChannel(_gradientCurve![1], offset); // Green
      _gradientCurve![2] = _rollChannel(_gradientCurve![2], offset); // Blue
    }
  }

  // Helper method based on your provided rollList, adapted for Float64List
  List<double> _rollChannel(List<double> list, int offset) {
    if (list.isEmpty) return [];

    // Calculate the actual effective shift
    int effectiveShift = offset % list.length;
    if (effectiveShift == 0) {
      return list; // Return a copy
    }

    // Create a new list for the rolled result
    List<double> rolled = List<double>.filled(list.length, 0);

    // Roll by +offset (forward shift)
    for (int i = 0; i < list.length; i++) {
      // New index = (current index + shift) % length
      int newIndex = (i + effectiveShift) % list.length;

      // Ensure the index is positive (crucial for Dart's modulo behavior with negative numbers)
      if (newIndex < 0) {
        newIndex += list.length;
      }

      rolled[newIndex] = list[i];
    }
    return rolled;
  }
}

List<List<double>> transpose3xNToNx3(List<List<double>> matrix3xN) {
  // 1. Basic Validation
  if (matrix3xN.isEmpty) {
    return []; // Handle empty input gracefully.
  }
  if (matrix3xN.length != 3) {
    throw ArgumentError(
      'The input matrix must have exactly 3 rows for a 3xN transposition.',
    );
  }

  // N is the number of columns in the 3xN matrix, which is the length
  // of any of the rows (assuming a well-formed matrix).
  final int numColsN = matrix3xN[0].length;
  const int numRows3 = 3;

  // 2. Initialize the result matrix (Nx3).
  // It will have N rows and 3 columns.
  final List<List<double>> matrixNx3 = List.generate(
    numColsN, // N rows
    (_) => List<double>.filled(numRows3, 0.0), // 3 columns filled with 0.0
  );

  // 3. Perform the transposition:
  // The element at matrix3xN[i][j] moves to matrixNx3[j][i].
  // i is the row index of the original matrix (0 to 2).
  // j is the column index of the original matrix (0 to N-1).
  for (int i = 0; i < numRows3; i++) {
    // Loop through original rows (i=0, 1, 2)
    // Validate that all rows have the same length (N)
    if (matrix3xN[i].length != numColsN) {
      throw ArgumentError(
        'All rows in the input matrix must have the same number of columns.',
      );
    }

    for (int j = 0; j < numColsN; j++) {
      // Loop through original columns (j=0 to N-1)
      matrixNx3[j][i] = matrix3xN[i][j];
    }
  }

  return matrixNx3;
}
