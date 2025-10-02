import 'dart:math';

/// A minimal Polynomial class to mimic NumPy's np.polynomial.Polynomial.
class Polynomial {
  final List<double>
  coeffs; // Coefficients: [c0, c1, c2, ...] where c0 is constant

  Polynomial(this.coeffs);

  /// Returns the polynomial evaluated at a given point x.
  double call(double x) {
    double result = 0.0;
    for (int i = 0; i < coeffs.length; i++) {
      result += coeffs[i] * pow(x, i);
    }
    return result;
  }

  /// Evaluates the polynomial over a list of x values.
  List<double> evaluate(List<double> x) {
    return x.map((val) => call(val)).toList();
  }

  /// Computes the derivative of the polynomial.
  Polynomial deriv() {
    if (coeffs.isEmpty || coeffs.length == 1) {
      return Polynomial([0.0]); // Derivative of constant is 0
    }
    List<double> dCoeffs = [];
    for (int i = 1; i < coeffs.length; i++) {
      dCoeffs.add(coeffs[i] * i.toDouble());
    }
    return Polynomial(dCoeffs);
  }

  /// Adds two polynomials.
  Polynomial operator +(Polynomial other) {
    int maxLen = max(coeffs.length, other.coeffs.length);
    List<double> newCoeffs = List.filled(maxLen, 0.0);

    for (int i = 0; i < maxLen; i++) {
      double c1 = i < coeffs.length ? coeffs[i] : 0.0;
      double c2 = i < other.coeffs.length ? other.coeffs[i] : 0.0;
      newCoeffs[i] = c1 + c2;
    }
    // Remove trailing zeros
    while (newCoeffs.isNotEmpty &&
        newCoeffs.last == 0.0 &&
        newCoeffs.length > 1) {
      newCoeffs.removeLast();
    }
    return Polynomial(newCoeffs);
  }

  /// Multiplies the polynomial by another polynomial.
  Polynomial operator *(Polynomial other) {
    int maxLen = coeffs.length + other.coeffs.length - 1;
    List<double> newCoeffs = List.filled(maxLen, 0.0);

    for (int i = 0; i < coeffs.length; i++) {
      for (int j = 0; j < other.coeffs.length; j++) {
        newCoeffs[i + j] += coeffs[i] * other.coeffs[j];
      }
    }
    return Polynomial(newCoeffs);
  }
}

/// Produces a 1D Gaussian or Gaussian-derivative filter kernel as a List<double>.
List<double> _gaussianKernel1d(double sigma, int order, int arrayLen) {
  // 1. Radius Calculation and Clamping
  sigma = max(0.00001, sigma);
  int radius = max(1, (4.0 * sigma).round());
  radius = min(((arrayLen - 1) / 2).toInt(), radius);
  radius = max(radius, 1);

  if (order < 0) {
    throw ValueError("Order must be non-negative");
  }

  // 2. Kernel Generation (Gaussian function: exp(-x^2 / (2*sigma^2)))
  // p = np.polynomial.Polynomial([0, 0, -0.5 / (sigma * sigma)])
  Polynomial p = Polynomial([0.0, 0.0, -0.5 / (sigma * sigma)]);

  // x = np.arange(-radius, radius + 1)
  List<double> x = List<double>.generate(
    2 * radius + 1,
    (i) => (i - radius).toDouble(),
  );

  // phi_x = np.exp(p(x), dtype=np.double)
  List<double> pXvalues = p.evaluate(x);
  List<double> phiX = pXvalues.map((val) => exp(val)).toList();

  // phi_x /= phi_x.sum() (Normalization)
  double sumPhiX = phiX.fold(0.0, (prev, element) => prev + element);
  phiX = phiX.map((val) => val / sumPhiX).toList();

  // 3. Gaussian Derivative Logic
  if (order > 0) {
    // q = np.polynomial.Polynomial([1])
    Polynomial q = Polynomial([1.0]);

    // p_deriv = p.deriv()
    Polynomial pDeriv = p.deriv();

    // Loop for derivative order
    for (int i = 0; i < order; i++) {
      // q = q.deriv() + q * p_deriv
      q = q.deriv() + (q * pDeriv);
    }

    // phi_x *= q(x) (Apply the derivative factor)
    List<double> qXValues = q.evaluate(x);
    for (int i = 0; i < phiX.length; i++) {
      phiX[i] *= qXValues[i];
    }
  }

  return phiX;
}

// 1D Convolution with mode="same"
List<double> _convolveSame(List<double> array, List<double> kernel) {
  int arrayLen = array.length;
  int kernelLen = kernel.length;
  int radius = (kernelLen / 2).floor();
  List<double> output = List<double>.filled(arrayLen, 0.0);

  // Extend the array with edge values for 'same' mode padding
  List<double> paddedArray = [];
  for (int i = 0; i < radius; i++) {
    paddedArray.add(array[0]); // Pad start with first element
  }
  paddedArray.addAll(array);
  for (int i = 0; i < radius; i++) {
    paddedArray.add(array[arrayLen - 1]); // Pad end with last element
  }

  // Perform convolution
  for (int i = 0; i < arrayLen; i++) {
    double sum = 0.0;
    for (int j = 0; j < kernelLen; j++) {
      // The kernel is often reversed in convolution, but a symmetric Gaussian
      // kernel makes this moot. We use the common implementation for same mode.
      sum += paddedArray[i + j] * kernel[kernelLen - 1 - j];
    }
    output[i] = sum;
  }
  return output;
}

// --- Main Blur Functions ---

/// Applies fast Gaussian blur to a 1-dimensional array.
List<double> fastBlurArray(List<double> array, double sigma) {
  if (array.isEmpty) {
    throw ValueError("Cannot smooth an empty array");
  }
  List<double> kernel = _gaussianKernel1d(sigma, 0, array.length);
  return _convolveSame(array, kernel);
}

/// Applies a fast blur effect to the given pixel data (R, G, B channels).
///
/// Assumes pixels is a list of [R, G, B, R, G, B, ...] or similar structure
/// that can be broken into 3 separate lists.
List<List<double>> fastBlurPixels(List<List<double>> pixels, double sigma) {
  if (pixels.isEmpty) {
    throw ValueError("Cannot smooth an empty array");
  }

  // Assuming pixels is structured as [[R_data], [G_data], [B_data]]
  // where each inner list is a channel (matching the Python pixels[:, 0] structure)
  if (pixels.length < 3) {
    throw ArgumentError("Input pixels must have at least 3 channels (R, G, B)");
  }

  final List<double> rChannel = pixels[0];
  final List<double> gChannel = pixels[1];
  final List<double> bChannel = pixels[2];

  final int arrayLen = rChannel.length;
  List<double> kernel = _gaussianKernel1d(sigma, 0, arrayLen);

  // pixels[:, 0] = np.convolve(pixels[:, 0], kernel, mode="same")
  List<double> rBlurred = _convolveSame(rChannel, kernel);

  // pixels[:, 1] = np.convolve(pixels[:, 1], kernel, mode="same")
  List<double> gBlurred = _convolveSame(gChannel, kernel);

  // pixels[:, 2] = np.convolve(pixels[:, 2], kernel, mode="same")
  List<double> bBlurred = _convolveSame(bChannel, kernel);

  // Return the modified/newly created array structure
  return [rBlurred, gBlurred, bBlurred];
}

class ValueError implements Exception {
  final String message;
  ValueError(this.message);
  @override
  String toString() => 'ValueError: $message';
}

// Assume the following functions and classes are available from the previous response:
// - _gaussianKernel1d(sigma, order, arrayLen)
// - ValueError
// - Polynomial (and its associated methods)
// - _convolveValid(array, kernel)

// Since the array length changes during padding, we need a separate
// _convolveValid function to match the mode='valid' behavior.
List<double> _convolveValid(List<double> array, List<double> kernel) {
  int arrayLen = array.length;
  int kernelLen = kernel.length;

  if (arrayLen < kernelLen) {
    // Valid mode requires the array to be at least as long as the kernel.
    return [];
  }

  int outputLen = arrayLen - kernelLen + 1;
  List<double> output = List<double>.filled(outputLen, 0.0);

  // Perform convolution in 'valid' mode
  for (int i = 0; i < outputLen; i++) {
    double sum = 0.0;
    // The kernel is often reversed in convolution.
    for (int j = 0; j < kernelLen; j++) {
      sum += array[i + j] * kernel[kernelLen - 1 - j];
    }
    output[i] = sum;
  }
  return output;
}

/// Smooths a 1D array via a Gaussian filter using reflection padding
/// and 'valid' convolution mode.
List<double> smooth(List<double> x, double sigma) {
  if (x.isEmpty) {
    throw ValueError("Cannot smooth an empty array");
  }

  // 1. Determine Kernel and Radius
  // kernel_radius = max(1, int(round(4.0 * sigma)))
  int kernelRadius = max(1, (4.0 * sigma).round());

  // filter_kernel = _gaussian_kernel1d(sigma, 0, kernel_radius)
  // NOTE: The Python code uses kernel_radius for array_len here, but
  // the definition of _gaussian_kernel1d uses it to limit the final
  // kernel size (radius). The radius determines the length: 2*radius + 1.
  List<double> filterKernel = _gaussianKernel1d(sigma, 0, kernelRadius);
  int kernelLen = filterKernel.length;

  // 2. Determine Required Extended Length (len(x) + len(filter_kernel) - 1)
  int extendedInputLen = x.length + kernelLen - 1;
  List<double> xMirrored = List.from(x); // Start with a copy

  // 3. Mirror Padding Loop (Equivalent to np.r_ and the while loop)
  // This logic is complex because it mirrors iteratively to avoid crashing
  // if len(x) is tiny compared to the required padding.
  while (xMirrored.length < extendedInputLen) {
    // mirror_len = min(len(x_mirrored), (extended_input_len - len(x_mirrored)) // 2)
    int remainingPadding = extendedInputLen - xMirrored.length;
    int mirrorLen = min(xMirrored.length, (remainingPadding / 2).floor());

    // Build the new mirrored array: [Start Mirror] + [x_mirrored] + [End Mirror]
    List<double> newMirrored = [];

    // Start Mirror: x_mirrored[mirror_len - 1 :: -1] (Reversed slice from index mirror_len - 1 down to 0)
    // The slice x_mirrored[:mirror_len] reversed
    for (int i = mirrorLen - 1; i >= 0; i--) {
      newMirrored.add(xMirrored[i]);
    }

    // Original array
    newMirrored.addAll(xMirrored);

    // End Mirror: x_mirrored[-1 : -(mirror_len + 1) : -1] (Reversed slice from last element back for mirror_len items)
    // The slice x_mirrored[-mirror_len:] reversed
    for (int i = xMirrored.length - 1; i >= xMirrored.length - mirrorLen; i--) {
      newMirrored.add(xMirrored[i]);
    }

    xMirrored = newMirrored;
  }

  // 4. Convolve
  // y = np.convolve(x_mirrored, filter_kernel, mode="valid")
  List<double> y = _convolveValid(xMirrored, filterKernel);

  // 5. Assertion and Return
  // assert len(y) == len(x)
  if (y.length != x.length) {
    throw StateError(
      "Convolution output length ${y.length} does not match input length ${x.length}.",
    );
  }

  return y;
}
