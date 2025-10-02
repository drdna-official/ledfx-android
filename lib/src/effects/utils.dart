import 'dart:math';

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

/// A fixed-size, auto-dropping circular buffer (like Python's collections.deque(maxlen=...)).
class CircularBuffer<T> {
  final int maxLength;
  final List<T> _buffer;
  int _head = 0; // Index where the next element will be written
  int _currentLength =
      0; // The actual number of elements currently in the buffer

  /// Initializes the buffer with a fixed maximum size.
  CircularBuffer(this.maxLength)
    : assert(maxLength > 0),
      _buffer = List<T>.filled(maxLength, null as T, growable: false);

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

  /// Returns a standard List containing the current elements in order
  /// (from oldest to newest).
  List<T> toList() {
    if (_currentLength == 0) return [];

    final result = List<T>.filled(_currentLength, null as T, growable: true);
    for (int i = 0; i < _currentLength; i++) {
      // Calculate the index for reading, starting from the oldest element
      int readIndex = (_head - _currentLength + i + maxLength) % maxLength;
      result[i] = _buffer[readIndex];
    }
    return result;
  }

  int get length => _currentLength;

  T operator [](int index) {
    if (index >= _currentLength || index < 0) {
      throw RangeError.index(index, this, 'index', null, _currentLength);
    }
    // Calculate the physical index in the underlying list
    int readIndex = (_head - _currentLength + index + maxLength) % maxLength;
    return _buffer[readIndex];
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
