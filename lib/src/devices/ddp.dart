// ignore_for_file: constant_identifier_names

import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:ledfx/src/devices/device.dart';

class DDPDevice extends UDPDevice {
  static const int VER1 = 0x01; // DDP Version 1
  static const int PUSH = 0x80; // PUSH flag (used for 'last' packet)
  static const int DATATYPE = 0x01; // Data Type (e.g., RGB data)
  static const int SOURCE = 0x00; // Source ID
  static const int MAX_PIXELS =
      480; // Example max data length per packet (adjust if needed)
  static const int MAX_DATALEN =
      MAX_PIXELS * 3; // Example max data length per packet (adjust if needed)
  DDPDevice({
    required super.ipAddr,
    super.port = 4048,
    required super.id,
    required super.ledfx,
    required super.config,
  });

  String deviceType = "DDP";
  int frameCount = 0;
  bool connectionWarning = false;

  @override
  void flush(List<Float32List> data) {
    frameCount += 1;
    try {
      if (socket == null) {
        throw Exception("Socket not initialised");
      }
      if (destination == null || destination!.isEmpty) {
        throw Exception("No valid destination");
      }
      DDPDevice.sendOut(
        sock: socket!,
        dest: InternetAddress(destination!),
        port: port,
        data: data,
        frameCount: frameCount,
      );
    } catch (e) {
      debugPrint("DDP Device-Flush Error - ${e.toString()}");
    }
  }

  // Args:
  //   sock (RawDatagramSocket): The socket to send the packet over.
  //   dest (InternetAddress): The destination IP address.
  //   port (int): The destination port number.
  //   data (List<Float32List>): The data to be sent in the packet.
  //   frame_count(int): The count of frames.
  static void sendOut({
    required RawDatagramSocket sock,
    required InternetAddress dest,
    required int port,
    required List<Float32List> data,
    required int frameCount,
  }) {
    final int sequence = frameCount % 15 + 1;

    final int totalBytes = data.length * 3;
    final Uint8List byteData = Uint8List(totalBytes);
    int byteIndex = 0;

    for (final Float32List pixelRow in data) {
      for (final double value in pixelRow) {
        byteData[byteIndex++] = value.toInt().clamp(0, 255);
      }
    }

    // 3. packets, remainder = divmod(len(byteData), DDPDevice.MAX_DATALEN)
    final int dataLength = byteData.length;
    final int maxDataLen = MAX_DATALEN;

    int packetCount = dataLength ~/ maxDataLen; // Integer division
    final int remainder = dataLength % maxDataLen;

    if (remainder != 0) {
      packetCount += 1;
    }
    final int totalPackets =
        packetCount; // The total number of packets to send (1-indexed count for DDP header)

    // 4. for i in range(packets + 1):
    // Since 'packets' here is 0-indexed count, the loop runs from 0 to totalPackets - 1.
    for (int i = 0; i < totalPackets; i++) {
      final int dataStart = i * maxDataLen;

      int dataEnd = dataStart + maxDataLen;

      dataEnd = min(dataEnd, dataLength);

      // Slice the data
      final Uint8List dataSlice = byteData.sublist(dataStart, dataEnd);

      // The 'last' flag is true if the current index 'i' is the last packet index (totalPackets - 1).
      final bool isLast = i == (totalPackets - 1);

      DDPDevice.sendPacket(
        sock,
        dest,
        port,
        sequence,
        totalPackets,
        dataSlice,
        isLast,
      );
    }
  }

  // Args:
  //     sock (RawDatagramSocket): The socket to send the packet over.
  //     dest (InternetAddress): The destination IP address.
  //     port (int): The destination port number.
  //     sequence (int): The sequence number of the packet.
  //     packetCount (int): The total number of packets.
  //     data (Uint8List): The data to be sent in the packet.
  //     last (bool): Indicates if this is the last packet in the sequence.
  static void sendPacket(
    RawDatagramSocket sock,
    InternetAddress dest,
    int port,
    int sequence,
    int packetCount,
    Uint8List data,
    bool last,
  ) {
    final int bytesLength = data.length;

    // The DDP header size: !BBBBLH means 1+1+1+1+4+2 = 10 bytes
    const int headerSize = 10;

    // Use a ByteData buffer to construct the header with explicit endianness (Big-Endian: !)
    final headerBuffer = ByteData(headerSize);

    // 1. VER1 | PUSH/0 (1 byte: B)
    int headerFlags = VER1 | (last ? PUSH : 0);
    headerBuffer.setUint8(0, headerFlags);

    // 2. sequence (1 byte: B)
    headerBuffer.setUint8(1, sequence);

    // 3. DATATYPE (1 byte: B)
    headerBuffer.setUint8(2, DATATYPE);

    // 4. SOURCE (1 byte: B)
    headerBuffer.setUint8(3, SOURCE);

    // 5. total data length (packet_count * MAX_DATALEN) (4 bytes: L - unsigned long)
    // Note: DDP uses a 4-byte total length field.
    int totalDataLength = packetCount * MAX_DATALEN;
    headerBuffer.setUint32(4, totalDataLength, Endian.big);

    // 6. bytes_length (actual data size in this packet) (2 bytes: H - unsigned short)
    headerBuffer.setUint16(8, bytesLength, Endian.big);

    // --- Construct the final UDP packet ---
    // Python: udpData = header + bytes(data)

    // Create a single Uint8List containing both header and data
    final int packetLength = headerSize + bytesLength;
    final Uint8List udpData = Uint8List(packetLength)
      ..setAll(0, headerBuffer.buffer.asUint8List()) // Copy header
      ..setAll(headerSize, data); // Copy data

    // --- Send the packet ---
    sock.send(udpData, dest, port);
  }
}
