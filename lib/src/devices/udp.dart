import 'dart:developer' show log;
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:ledfx/src/devices/device.dart';
import 'package:ledfx/src/devices/packets.dart';

abstract class UDPDevice extends NetworkedDevice implements AsyncInitDevice {
  UDPDevice({
    required super.ipAddr,
    super.refreshRate,
    required this.port,
    required super.id,
    required super.ledfx,
    required super.config,
  });

  int port;

  RawDatagramSocket? _socket;
  RawDatagramSocket? get socket => _socket;

  @override
  Future<void> activate() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    super.activate();
  }

  @override
  void deactivate() {
    super.deactivate();
    _socket = null;
  }
}

class RealtimeUDPDevice extends UDPDevice {
  RealtimeUDPDevice({
    required super.ipAddr,
    required super.port,
    super.refreshRate,
    required this.udpPacketType,
    this.timeout = 1,
    this.minimizeTraffic = true,
    required super.id,
    required super.ledfx,
    required super.config,
  }) : lastFrame = List.filled(
         config.pixelCount,
         Float64List.fromList(List.filled(3, -1)),
       ),
       lastFrameSendTime = DateTime.now().millisecondsSinceEpoch,
       deviceType = "UDP Device";

  String deviceType;
  String udpPacketType;
  int timeout;
  bool minimizeTraffic;

  late List<Float64List> lastFrame;
  late int lastFrameSendTime;

  @override
  void flush(List<Float64List> data) {
    try {
      chooseAndSend(data);
      lastFrame = data;
    } catch (e) {
      log("Error: ${e.toString()}");
      activate();
    }
  }

  List<Uint8List> clampToByte(List<Float64List> data) {
    return data
        .map(
          (e) => Uint8List.fromList(
            e.map((i) => i.toInt().clamp(0, 255)).toList(),
          ),
        )
        .toList();
  }

  void chooseAndSend(List<Float64List> floatData) {
    final int frameSize = floatData.length;
    final bool frameIsSame = minimizeTraffic && floatData == lastFrame;

    final data = clampToByte(floatData);
    switch ((udpPacketType, frameSize)) {
      case ("DRGB", <= 490):
        final udpData = Packets.buidDRGBpacket(data, timeout);
        transmitPacket(udpData, frameIsSame);
        break;
      case ("WARLS", <= 255):
        final udpData = Packets.buildWARLSpacket(data, timeout);
        transmitPacket(udpData, frameIsSame);
        break;
      case ("DNRGB", _):
        final numberOfPackets = (frameSize / 489).ceil();
        for (int i = 0; i < numberOfPackets; i++) {
          int start = i * 489;
          int end = start + 489;
          end = min(end, data.length);
          final udpData = Packets.buidDNRGBpacket(
            data.sublist(start, end),
            start,
            timeout,
          );
          transmitPacket(udpData, frameIsSame);
        }
        break;
      default:
        log(
          """UDP packet is configured incorrectly (please choose a packet that supports $pixelCount LEDs): 
          https://kno.wled.ge/interfaces/udp-realtime/#udp-realtime \n Falling back to supported udp packet.""",
        );

        if (frameSize < 255) {
          //DRGB
          final udpData = Packets.buidDRGBpacket(data, timeout);
          transmitPacket(udpData, frameIsSame);
        } else {
          // DNRGB
          final numberOfPackets = (frameSize / 489).ceil();
          for (int i = 0; i < numberOfPackets; i++) {
            int start = i * 489;
            int end = start + 489;
            final udpData = Packets.buidDNRGBpacket(
              data.getRange(start, end).toList(),
              start,
              timeout,
            );
            transmitPacket(udpData, frameIsSame);
          }
        }
    }
  }

  void transmitPacket(List<int> packet, bool frameIsSame) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    if (frameIsSame) {
      final halfTimeout =
          ((((timeout * refreshRate) - 1) ~/ 2) / refreshRate) * 1000;

      if (timestamp > lastFrameSendTime + halfTimeout) {
        if (destination != null) {
          // _socket!.send(packet, InternetAddress("192.168.0.150"), 12345);
          _socket!.send(packet, InternetAddress(destination!), port);
          lastFrameSendTime = timestamp;
        }
      }
    } else {
      if (destination != null) {
        // _socket!.send(packet, InternetAddress("192.168.0.150"), 12345);

        _socket!.send(packet, InternetAddress(destination!), port);
        lastFrameSendTime = timestamp;
      }
    }
  }
}
