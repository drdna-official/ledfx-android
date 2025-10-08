import 'dart:typed_data';

import 'package:matrix2d/matrix2d.dart';

class Packets {
  static List<int> buidDRGBpacket(List<Uint8List> data, [int? timeout]) {
    // Generic DRGB packet encoding
    // Max LEDs: 490

    // Header: [2, timeout]
    // Byte 	Description
    // 2 + n*3 	Red Value
    // 3 + n*3 	Green Value
    // 4 + n*3 	Blue Value

    List<int> header = [2, timeout ?? 1];
    return [...header, ...data.flatten];
  }

  static List<int> buidDNRGBpacket(
    List<Uint8List> data,
    int ledStartIndex, [
    int? timeout,
  ]) {
    // Generic DNRGB packet encoding
    // Max LEDs: 489 / packet

    // Header: [4, timeout, start index high byte, start index low byte]
    // Byte 	Description
    // 4 + n*3 	Red Value
    // 5 + n*3 	Green Value
    // 6 + n*3 	Blue Value
    // Use a ByteData buffer for easier manipulation of multi-byte integers.
    final headerBuffer = ByteData(4);

    // Header: [4, timeout, start index high byte, start index low byte]
    headerBuffer.setUint8(0, 4);
    headerBuffer.setUint8(1, timeout ?? 1);
    headerBuffer.setUint8(2, (ledStartIndex >> 8) & 0xFF);
    headerBuffer.setUint8(3, ledStartIndex & 0xFF);

    final List<int> flattened = data.flatten.cast();

    // Calculate the total packet size: 4 bytes for the header + 3 bytes per LED.
    final totalSize = 4 + (flattened.length * 3);
    final packetBuffer = Uint8List(totalSize);

    // Copy header bytes to the final packet buffer.
    packetBuffer.setAll(0, headerBuffer.buffer.asUint8List());

    // Flatten the RGB data and copy it to the packet buffer.
    packetBuffer.setAll(4, flattened);

    return packetBuffer.toList();
  }

  // TODO: Implement
  static List<int> buildWARLSpacket(List<Uint8List> data, [int? timeout]) {
    //     Generic WARLS packet encoding
    // Max LEDs: 255

    // Header: [1, timeout]
    // Byte 	Description
    // 2 + n*4 	LED Index
    // 3 + n*4 	Red Value
    // 4 + n*4 	Green Value
    // 5 + n*4 	Blue Value
    List<int> header = [2, timeout ?? 1];

    return [...header];
  }
}
