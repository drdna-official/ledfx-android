import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';
import 'dart:ui';

import 'package:ledfx/src/devices/ddp.dart';
import 'package:ledfx/src/devices/device.dart';
import 'package:http/http.dart' as http;
import 'package:ledfx/src/devices/udp.dart';
import 'package:nanoid/nanoid.dart';

enum WLEDSyncMode { udp, ddp, e131 }

class WLEDDevice extends NetworkedDevice {
  WLEDDevice({
    required super.ipAddr,
    super.refreshRate,
    required this.syncMode,
    this.timeout = 1,
    required super.id,
    required super.ledfx,
    required super.config,

    // required int port,
    // required String udpPacketType,
  });

  WLEDSyncMode syncMode;
  int timeout;

  NetworkedDevice? subdevice;
  WLED? wled;

  @override
  void flush(List<Float64List> data) {
    subdevice?.flush(data);
  }

  @override
  void activate() {
    if (subdevice == null) setupSubdevice();
    subdevice!.activate();
    super.activate();
  }

  @override
  void deactivate() {
    if (subdevice != null) subdevice!.deactivate();
    super.deactivate();
  }

  void setupSubdevice() {
    if (subdevice != null) subdevice!.deactivate();

    subdevice = switch (syncMode) {
      WLEDSyncMode.udp => RealtimeUDPDevice(
        id: nanoid(10),
        ipAddr: ipAddr,
        port: 21324,
        timeout: timeout,
        udpPacketType: "DNRGB",
        minimizeTraffic: true,
        ledfx: ledfx,
        config: config,
      ),
      WLEDSyncMode.ddp => DDPDevice(
        id: nanoid(10),
        ipAddr: ipAddr,
        port: 4048,
        ledfx: ledfx,
        config: config,
      ),
      WLEDSyncMode.e131 => RealtimeUDPDevice(
        id: nanoid(10),
        ipAddr: ipAddr,
        port: 21324,
        udpPacketType: "DNRGB",
        minimizeTraffic: true,
        ledfx: ledfx,
        config: config,
      ),
    };
    subdevice!.destination = destination;
  }

  @override
  Future<void> resolveAddress([VoidCallback? callback]) async {
    await super.resolveAddress(callback);
    if (subdevice != null) subdevice!.destination = destination;
  }

  @override
  Future<void> initialize() async {
    await super.initialize();
    wled = WLED(ipAddr: destination!);
    final wledConfig = await wled!.getConfig();
    if (wledConfig == null) return;
    // Update Config
    config
      ..name = wledConfig.name
      ..pixelCount = wledConfig.ledCount
      ..rgbwLED = wledConfig.rgbwLED;

    setupSubdevice();
  }
}

// Collection of WLED Helper Functions
class WLED {
  WLED({required this.ipAddr, this.rebootFlag = false});

  final String ipAddr;
  final bool rebootFlag;

  static final syncModePortMap = {"DDP": 4048, "E131": 5568, "ARTNET": 6454};

  Future<Map<String, dynamic>?> _requestGET(String endpoint) async {
    try {
      print("requesting config at http://$ipAddr/$endpoint");
      final response = await http.get(Uri.parse("http://$ipAddr/$endpoint"));
      // final response = await http.get(Uri.parse("http://192.168.0.150"));
      if (response.statusCode == 200) {
        // The request was successful (status code 200).
        // Parse the JSON data from the response body.
        final Map<String, dynamic> data = json.decode(response.body);
        log('Data received: $data');
        // You can now use the 'data' map to update your UI or process the information.
        return data;
      }
    } catch (e) {
      log("error ${e.toString()}");
    }

    return null;
  }

  Future<Map<String, dynamic>?> _requestPOST(String endpoint) async {
    try {
      final response = await http.post(Uri.parse("http://$ipAddr/$endpoint"));
      if (response.statusCode == 200) {
        // The request was successful (status code 200).
        // Parse the JSON data from the response body.
        final Map<String, dynamic> data = json.decode(response.body);
        log('Data received: $data');
        // You can now use the 'data' map to update your UI or process the information.
        return data;
      }
    } catch (e) {
      log("error ${e.toString()}");
    }

    return null;
  }

  Future<void> getSyncSetting() async {
    final syncResp = await _requestGET("json/cfg");
    // Set and parse SyncSetting from json response
  }

  Future<WLEDConfig?> getConfig() async {
    try {
      final Map<String, dynamic>? configResp = await _requestGET("json/info");
      if (configResp == null) {
        throw Exception("could not fetch WLED config");
      }
      return WLEDConfig(
        ledCount: configResp["leds"]?["count"],
        rgbwLED: configResp["leds"]?["rgbw"],
        build: configResp["vid"],
        name: configResp["name"],
        mac: configResp["mac"],
        rows: configResp["matrix"]?["h"],
      );
      // Set and parse Config from json response

      //     wled_config = response.json()

      // if "brand" not in wled_config:
      //     raise ValueError(
      //         f"WLED {self.ip_address}: Device is not WLED compatible"
      //     )

      // _LOGGER.info(
      //     f"WLED compatible device brand:{wled_config['brand']} at {self.ip_address} configuration received"
      // )

      // return wled_config
    } catch (e) {
      print(e.toString());
      return null;
    }
  }

  static bool wledDDPsupport(int build) {
    //https://github.com/Aircoookie/WLED/blob/main/CHANGELOG.md#build-2110060
    if (build >= 2110060) {
      return true;
    } else {
      return false;
    }
  }
}

class WLEDConfig {
  final int ledCount;
  final bool rgbwLED;
  final int build;
  final String name;
  final String mac;
  final String? rows;

  const WLEDConfig({
    required this.ledCount,
    required this.rgbwLED,
    required this.build,
    required this.name,
    required this.mac,
    required this.rows,
  });
}
