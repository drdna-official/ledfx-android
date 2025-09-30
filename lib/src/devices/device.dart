import 'dart:developer';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:ledfx/src/devices/packets.dart';
import 'package:ledfx/utils.dart';
import 'package:n_dimensional_array/n_dimensional_array.dart';

abstract class Device {
  Device({required this.name, this.fps = 60, required this.pixelCount});

  String name;
  // final String? icon;
  // TODO: - Implement FPS
  int fps;
  int pixelCount;

  bool _active = false;
  bool get isActive => _active;

  bool _online = true;
  bool get isOnline => _online;

  NdArray? _pixels;

  void activate() {
    _pixels = NdArray.fromList(List.filled(pixelCount, List.filled(3, 0)));
    _active = true;
  }

  void deactivate() {
    _pixels = null;
    _active = false;
  }

  void setOffline() {
    deactivate();
    _online = false;

    // TODO: Fire Events in stream
    //self._ledfx.events.fire_event(DevicesUpdatedEvent(self.id))
  }

  ///Flushes the provided data to the device. This abstract method must be
  ///overwritten by the device implementation.
  void flush(NdArray data);

  Future<void> postamble() async {
    return;
  }

  void updatePixels(String virtualID, List<(NdArray, int, int)> data) {
    if (_active == false) {
      debugPrint("Can't update inactive device: $name");
      return;
    }

    for (final (pixels, _, _) in data) {
      if (pixels.shape.isNotEmpty && pixels.shape[0] != 0) {
        if (pixels.shape.first == 3 || _pixels?.shape == pixels.shape) {
          _pixels = pixels;
        }
      }
    }

    //     if self.priority_virtual:
    //     if virtual_id == self.priority_virtual.id:
    //         frame = self.assemble_frame()
    //         self.flush(frame)
    //         # _LOGGER.debug(f"Device {self.id} flushed by Virtual {virtual_id}")

    //         self._ledfx.events.fire_event(
    //             DeviceUpdateEvent(self.id, frame)
    //         )
    // else:
    //     _LOGGER.warning(
    //         f"Flush skipped as {self.id} has no priority_virtual"
    //     )
  }
}

abstract class NetworkedDevice extends Device {
  NetworkedDevice({
    required super.name,
    required super.pixelCount,
    super.fps,
    required this.ipAddr,
  });

  String ipAddr;

  String? _destination;
  String? get destination => () {
    if (_destination == null) {
      resolveAddress();
      return null;
    } else {
      return _destination!;
    }
  }();
  set destination(String? dest) => _destination = dest;

  Future<void> initialize() async {
    _destination = null;
    await resolveAddress();
  }

  @override
  void activate() {
    if (_destination == null) {
      debugPrint("Error: Not Online");
      resolveAddress().then((_) {
        activate();
      });
    } else {
      _online = true;
      super.activate();
    }
  }

  Future<void> resolveAddress([VoidCallback? callback]) async {
    try {
      _destination = await resolveDestination(ipAddr);
      _online = true;
      if (callback != null) callback();
    } catch (e) {
      _online = false;
      debugPrint(e.toString());
    }
  }
}

abstract class UDPDevice extends NetworkedDevice {
  UDPDevice({
    required super.name,
    required super.pixelCount,
    required super.ipAddr,
    super.fps,
    required this.port,
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
    required super.name,
    required super.pixelCount,
    required super.ipAddr,
    required super.port,
    super.fps,
    required this.udpPacketType,
    this.timeout = 1,
    this.minimizeTraffic = true,
  }) : lastFrame = NdArray.fromList(
         List.filled(pixelCount, List.filled(3, -1)),
       ),
       lastFrameSendTime = DateTime.now().millisecondsSinceEpoch,
       deviceType = "UDP Device";

  String deviceType;
  String udpPacketType;
  int timeout;
  bool minimizeTraffic;

  late NdArray lastFrame;
  late int lastFrameSendTime;

  @override
  void flush(NdArray data) {
    try {
      chooseAndSend(data);
      lastFrame = data;
    } catch (e) {
      log("Error: ${e.toString()}");
      activate();
    }
  }

  void chooseAndSend(NdArray data) {
    final int frameSize = data.length;
    final bool frameIsSame = minimizeTraffic && data == lastFrame;
    log("Frame Size/Pixel Count = $frameSize");

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
          final udpData = Packets.buidDNRGBpacket(
            NdArray.fromList(data.data.getRange(start, end).toList()),
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
              NdArray.fromList(data.data.getRange(start, end).toList()),
              start,
              timeout,
            );
            transmitPacket(udpData, frameIsSame);
          }
        }
    }
  }

  void transmitPacket(packet, bool frameIsSame) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    if (frameIsSame) {
      final halfTimeout = ((((timeout * fps) - 1) ~/ 2) / fps) * 1000;

      if (timestamp > lastFrameSendTime + halfTimeout) {
        if (_destination != null) {
          _socket!.send([111], InternetAddress(_destination!), port);
          lastFrameSendTime = timestamp;
        }
      }
    } else {
      if (_destination != null) {
        _socket!.send([111], InternetAddress(_destination!), port);
        lastFrameSendTime = timestamp;
      }
    }
  }
}
