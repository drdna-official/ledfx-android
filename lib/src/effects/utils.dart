import 'dart:math';
import 'dart:typed_data';

List<double> equallySpacedDoublesList(double start, double end, int count) {
  if (count <= 0) return <double>[];
  if (count == 1) return [start];

  final double step = (end - start) / (count - 1);
  return List<double>.generate(count, (i) => start + (i * step));
}

List<int> equallySpacedIntsList(int start, int end, int count) {
  if (count <= 0) return <int>[];
  if (count == 1) return [start];

  final double step = (end - start) / (count - 1);
  return List<int>.generate(count, (i) => (start + (i * step)).toInt());
}

double maxOfList(List<double> list) {
  if (list.isEmpty) return 0.0;
  return list.reduce(max);
}

void copyListContents<T>(List<T> destination, List<T> source) {
  if (destination.length != source.length) {
    throw ArgumentError(
      'Source and destination lists must have the same length for in-place copy.',
    );
  }
  for (int i = 0; i < source.length; i++) {
    destination[i] = source[i];
  }
}

/// Implements the circular shift functionality, equivalent to numpy.roll(array, shift, axis=0).
/// Shifts the elements of a list by 'offset' places.
List<T> rollList<T>(List<T> list, int offset) {
  if (list.isEmpty) {
    return [];
  }

  // Calculate the actual effective shift
  int effectiveShift = offset % list.length;
  if (effectiveShift == 0) {
    return List<T>.from(list); // No shift needed, return a copy
  }

  // Create a new list for the rolled result
  List<T> rolled = List<T>.filled(list.length, list[0]);

  // Determine the split point and copy the parts in reversed order
  for (int i = 0; i < list.length; i++) {
    // New index = (current index - shift) % length
    // Dart's % operator can return negative results, so we use the helper to ensure a positive index.
    int newIndex = (i + effectiveShift) % list.length;

    // Ensure the index is positive (crucial for Dart's modulo behavior)
    if (newIndex < 0) {
      newIndex += list.length;
    }

    rolled[newIndex] = list[i];
  }

  return rolled;
}

// T is used to represent the inner type (Float32List or List<double>)
List<T> getSlice<T>(List<T> data, int start, int stop, int step) {
  if (step == 0) {
    throw ArgumentError('Step cannot be zero.');
  }

  // Normalize the indices to handle negative values and bounds,
  // similar to how Python handles slicing.
  int N = data.length;

  // Default Python start/stop behavior
  if (start < 0) start += N;
  if (stop < 0) stop += N;

  // Python slicing allows stop indices past the end of the list.
  if (stop > N) stop = N;
  if (start > N) start = N;

  // Ensure start/stop are not negative after normalization
  if (start < 0) start = 0;
  if (stop < 0) stop = 0;

  // Determine the direction of the loop
  if (step > 0) {
    // Standard forward slice (e.g., [1:10:2])
    // Ensure start is less than stop
    if (start >= stop) return [];

    return List<T>.generate(
      ((stop - start - 1) ~/ step) + 1, // Calculate the number of elements
      (i) => data[start + i * step],
    );
  } else {
    // Reverse slice (e.g., [10:1:-1])
    // Ensure start is greater than stop
    if (start <= stop) return [];

    // The logic is slightly complex for negative step; a simpler while loop is clearer.
    List<T> result = [];
    int i = start;

    while (i > stop) {
      if (i >= 0 && i < N) {
        result.add(data[i]);
      }
      i += step;
    }
    return result;
  }
}

// Utility function to simulate numpy.linspace
List<double> linspace(double start, double end, int num) {
  if (num <= 1) {
    return [start];
  }
  final List<double> result = List<double>.filled(num, 0.0, growable: false);
  final double step = (end - start) / (num - 1);
  for (int i = 0; i < num; i++) {
    result[i] = start + i * step;
  }
  return result;
}

// --- Linear Interpolation Function (Equivalent to np.interp) ---
// This is a simplified implementation for the specific use case (uniform xp).
List<double> interp(List<double> x, List<double> xp, List<double> fp) {
  // Assuming xp (old) is uniformly spaced from 0 to 1, and x (new) is also 0 to 1.
  int N_xp = xp.length;
  List<double> result = [];

  // Calculate the step size on the original data (xp)
  double xpStep = N_xp > 1 ? xp[1] - xp[0] : 1.0;

  for (double target_x in x) {
    // 1. Find the index (i) where target_x falls
    // Index i is the point just before target_x
    double index_f = (target_x - xp[0]) / xpStep;
    int i = index_f.floor();

    // Handle bounds (clamping)
    if (i < 0) {
      result.add(fp[0]);
      continue;
    }
    if (i >= N_xp - 1) {
      result.add(fp[N_xp - 1]);
      continue;
    }

    // 2. Calculate the slope (m)
    double x0 = xp[i];
    double x1 = xp[i + 1];
    double y0 = fp[i];
    double y1 = fp[i + 1];

    double m = (y1 - y0) / (x1 - x0);

    // 3. Linear interpolation: y = y0 + m * (x - x0)
    double interpolated_y = y0 + m * (target_x - x0);
    result.add(interpolated_y);
  }
  return result;
}

List<Float32List> repeatAndTruncatePixels(
  List<Float32List> effectivePixels,
  int groupSize,
  int pixelCount,
) {
  if (effectivePixels.isEmpty || groupSize <= 0) {
    return [];
  }

  // 1. Repetition (Equivalent to np.repeat(..., axis=0))
  List<Float32List> repeatedPixels = [];

  // Iterate through each row in the original array
  for (final Float32List row in effectivePixels) {
    // Repeat the current row 'groupSize' times
    for (int i = 0; i < groupSize; i++) {
      // Add a reference to the row.
      // NOTE: This creates a shallow copy (a new list of references
      // to the same Float32List objects), which matches NumPy's behavior
      // after a repeat operation if the result isn't explicitly copied/modified.
      repeatedPixels.add(row);
    }
  }

  // 2. Truncation (Equivalent to [:pixel_count, :])
  // Slice the resulting array to only keep the first 'pixel_count' rows.
  // The Dart List.sublist method handles this perfectly.

  int actualLength = repeatedPixels.length;

  if (pixelCount >= actualLength) {
    // If pixel_count is larger than the repeated array size, return the full repeated array.
    return repeatedPixels;
  } else {
    // Return only the first 'pixel_count' rows.
    return repeatedPixels.sublist(0, pixelCount);
  }
}

/// A fixed-size, auto-dropping circular buffer (like Python's
/// collections.deque(maxlen=...)).
class CircularBuffer<T extends Object> {
  final int maxLength;
  // Use a nullable type internally to safely initialize the fixed-size list.
  final List<T?> _buffer;
  int _head = 0; // Index where the next element will be written
  int _currentLength =
      0; // The actual number of elements currently in the buffer

  /// Initializes the buffer with a fixed maximum size.
  CircularBuffer(this.maxLength)
    : assert(maxLength > 0),
      // Dart allows initializing a List<T?> with nulls safely.
      _buffer = List<T?>.filled(maxLength, null, growable: false);

  /// Adds a new item to the buffer. If the buffer is full, the oldest
  /// item is automatically overwritten (dropped).
  void append(T item) {
    _buffer[_head] = item;
    _head = (_head + 1) % maxLength;

    // Only increment length until the max is reached
    if (_currentLength < maxLength) {
      _currentLength++;
    }
  }

  /// Returns the actual number of elements currently in the buffer.
  int get length => _currentLength;

  /// Returns the contents of the buffer as a List<T>, ordered from oldest to newest.
  List<T> toList() {
    if (_currentLength == 0) {
      return <T>[];
    }

    final List<T> result = List<T>.filled(_currentLength, _buffer[0] as T);

    // The starting index for reading is the oldest element, which is the
    // element *after* the current head (where the next write will happen).
    int readStart = (_head - _currentLength + maxLength) % maxLength;

    for (int i = 0; i < _currentLength; i++) {
      int bufferIndex = (readStart + i) % maxLength;
      // We know these elements are non-null because we track _currentLength
      // and only append non-null T objects.
      result[i] = _buffer[bufferIndex] as T;
    }

    return result;
  }
}

/// Args:
///   name: The name (String) to be converted.
///
/// Returns:
///   The converted ID (String).
String generateId(String name) {
  // Replace all non-alphanumeric characters with a space and lowercase.
  // Dart RegExp: [^a-zA-Z0-9] matches anything NOT a letter or number.
  // The global case-insensitive flag 'i' is often implicit in Dart String methods,
  // but here we use toLowerCase() after the substitution for certainty.
  final RegExp nonAlphanumeric = RegExp(r"[^a-zA-Z0-9]");
  String part1 = name.replaceAll(nonAlphanumeric, " ").toLowerCase();

  // 3 & 4: Collapse multiple spaces (" +") into a single space (" "), then trim.
  // Dart RegExp: " +" matches one or more spaces.
  final RegExp multipleSpaces = RegExp(r" +");
  String result = part1.replaceAll(multipleSpaces, " ").trim();

  // 5. Replace spaces with hyphens ("-").
  result = result.replaceAll(" ", "-");

  // 6. Handle the empty string case.
  if (result.isEmpty) {
    result = "default";
  }

  return result;
}

/// A simple, non-blocking, fixed-size queue (Ring Buffer)
/// similar to a Python queue with a maxsize.
class FixedSizeQueue<T> {
  final int maxSize;
  final List<T> _buffer;
  int _head = 0; // The index for the next element to be written (enqueue)
  int _tail = 0; // The index for the next element to be read (dequeue)
  int _currentSize = 0; // The actual number of elements in the queue

  /// Initializes the queue with a fixed maximum size.
  FixedSizeQueue(this.maxSize)
    : assert(maxSize > 0),
      // Use a fixed-length list for efficient memory usage
      _buffer = List<T>.filled(maxSize, null as T, growable: false);

  /// Puts an item into the queue. If the queue is full,
  /// it will simply not add the item (non-blocking behavior).
  /// To make it blocking (like Python's queue.put()), you'd need async/await
  /// and synchronization primitives.
  bool put(T item) {
    if (_currentSize == maxSize) {
      // Queue is full, cannot add the item
      return false;
    }
    _buffer[_head] = item;
    _head = (_head + 1) % maxSize;
    _currentSize++;
    return true;
  }

  /// Gets an item from the queue. Returns null if the queue is empty.
  T? get() {
    if (_currentSize == 0) {
      // Queue is empty
      return null;
    }

    T item = _buffer[_tail];
    // Optionally, clear the slot (though not strictly necessary for a ring buffer)
    // _buffer[_tail] = null as T;

    _tail = (_tail + 1) % maxSize;
    _currentSize--;
    return item;
  }

  int get length => _currentSize;
  bool get isFull => _currentSize == maxSize;
  bool get isEmpty => _currentSize == 0;
}

/// Converts an array of Hues using provided saturation and value properties to an RGB array.
///
/// Args:
///   hues (List<double>): Array of hue values (0 to 1).
///   saturation (double between 0 and 1): The saturation.
///   value (double between 0 and 1): The value.
///
/// Returns:
///   List<Float32List>: An array of RGB values where each RGB value is in the range 0 to 255.
List<Float32List> hsvToRgb(List<double> hues, double saturation, double value) {
  if (hues.isEmpty) {
    return [];
  }

  int pixelCount = hues.length;
  List<Float32List> rgbArray = List.generate(pixelCount, (_) => Float32List(3));

  // The six possible values for R, G, B channels based on intermediate calculation
  final double p = value * (1.0 - saturation);
  final double q =
      value * (1.0 - saturation * 0.0); // f is 0 for i=0, q=v*(1-s*0)=v*(1-s)
  final double t =
      value *
      (1.0 - saturation * 1.0); // 1-f is 0 for i=0, t=v*(1-s*1)=v*(1-s*f)

  // Pre-calculate the six intermediate values, which are constant for a given S and V
  // The six possibilities for each channel (value, q, p, p, t, value)
  // We use this structure to simulate np.choose.
  const int HUE_SECTIONS = 6;
  final List<double> sectionValues = [
    value,
    value * (1.0 - saturation * 0.0), // Placeholder for q or t logic
    p,
    p,
    value * (1.0 - saturation * 0.0), // Placeholder for q or t logic
    value,
  ];

  for (int idx = 0; idx < pixelCount; idx++) {
    double hue = hues[idx];

    // --- Intermediate Calculations (Vectorized in Python) ---

    // 1. hue_i = hue * 6
    double hue_i = hue * 6.0;

    // 2. i = np.floor(hue_i).astype(int)
    int i = hue_i.floor().toInt();

    // 3. f = hue_i - i
    double f = hue_i - i;

    // Intermediate values for RGB conversion based on the fractional part 'f'.
    // NOTE: These must be calculated per pixel because they depend on 'f'.
    final double p_pixel = value * (1.0 - saturation);
    final double q_pixel = value * (1.0 - saturation * f);
    final double t_pixel = value * (1.0 - saturation * (1.0 - f));

    // 4. i = i % 6 (Ensure that i values are within the range [0, 5])
    int section = i % HUE_SECTIONS;

    // --- Assigning RGB components (Equivalent to np.choose) ---

    // Define the color component sequences for the current pixel's section.
    // This replaces the complex np.choose logic.
    late double R, G, B;

    switch (section) {
      case 0: // R = V, G = T, B = P
        R = value;
        G = t_pixel;
        B = p_pixel;
        break;
      case 1: // R = Q, G = V, B = P
        R = q_pixel;
        G = value;
        B = p_pixel;
        break;
      case 2: // R = P, G = V, B = T
        R = p_pixel;
        G = value;
        B = t_pixel;
        break;
      case 3: // R = P, G = Q, B = V
        R = p_pixel;
        G = q_pixel;
        B = value;
        break;
      case 4: // R = T, G = P, B = V
        R = t_pixel;
        G = p_pixel;
        B = value;
        break;
      case 5: // R = V, G = P, B = Q
        R = value;
        G = p_pixel;
        B = q_pixel;
        break;
      default:
        // This case should be covered by i % 6, but included for robustness.
        R = 0.0;
        G = 0.0;
        B = 0.0;
    }

    // 5. Scale to 0-255 range and store (Equivalent to return rgb * 255)
    rgbArray[idx][0] = R * 255.0;
    rgbArray[idx][1] = G * 255.0;
    rgbArray[idx][2] = B * 255.0;
  }

  return rgbArray;
}

List<Float32List> fillRainbow(
  List<Float32List> pixels,
  double initialHue,
  double deltaHue,
) {
  // The input 'pixels' array is used only to determine the final size (pixelCount).
  final int pixelCount = pixels.length;

  const double sat = 0.95;
  const double val = 1.0;

  // --- Create Hue Values (Equivalent to np.arange(...) ) ---

  List<double> hues = [];
  double currentHue = initialHue;

  // The loop runs exactly 'pixelCount' times, generating the precise number of hues needed.
  // This replaces np.arange(...) and the subsequent array slicing.
  for (int i = 0; i < pixelCount; i++) {
    hues.add(currentHue);
    currentHue += deltaHue;
  }

  // --- Convert to RGB ---
  // The hsvToRgb function is expected to return the final List<Float32List>
  // with dimensions [pixelCount, 3].
  return hsvToRgb(hues, sat, val);
}
