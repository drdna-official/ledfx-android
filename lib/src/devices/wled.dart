import 'dart:convert';
import 'dart:developer';
import 'dart:ui';

import 'package:ledfx/src/devices/device.dart';
import 'package:n_dimensional_array/domain/models/nd_array.dart';
import 'package:http/http.dart' as http;
import 'package:nanoid/nanoid.dart';

enum WLEDSyncMode { udp, ddp, e131 }

class WLEDDevice extends NetworkedDevice {
  WLEDDevice({
    required super.name,
    required super.pixelCount,
    required super.ipAddr,
    super.refreshRate,
    required this.syncMode,
    this.timeout = 1,
    required super.id,
    required super.ledfx,

    // required int port,
    // required String udpPacketType,
  });

  WLEDSyncMode syncMode;
  int timeout;

  NetworkedDevice? subdevice;
  WLED? wled;

  @override
  void flush(NdArray data) {
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
        name: name,
        pixelCount: pixelCount,
        ipAddr: ipAddr,
        port: 21324,
        timeout: timeout,
        udpPacketType: "DNRGB",
        minimizeTraffic: true,
        ledfx: ledfx,
      ),
      WLEDSyncMode.ddp => RealtimeUDPDevice(
        id: nanoid(10),
        name: name,
        pixelCount: pixelCount,
        ipAddr: ipAddr,
        port: 21324,
        udpPacketType: "DNRGB",
        minimizeTraffic: true,
        ledfx: ledfx,
      ),
      WLEDSyncMode.e131 => RealtimeUDPDevice(
        id: nanoid(10),
        name: name,
        pixelCount: pixelCount,
        ipAddr: ipAddr,
        port: 21324,
        udpPacketType: "DNRGB",
        minimizeTraffic: true,
        ledfx: ledfx,
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
    final config = wled!.getConfig();
    // Update Config

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
      final response = await http.get(Uri.parse("http://$ipAddr/$endpoint"));
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
      return WLEDConfig(
        ledCount: configResp!["leds"]["count"],
        mode: configResp["leds"]["rgbw"],
        build: configResp["vid"],
        name: configResp["name"],
        mac: configResp["mac"],
        rows: configResp["matrix"]["h"],
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
    }
  }
}

class WLEDConfig {
  final int ledCount;
  final String mode;
  final String build;
  final String name;
  final String mac;
  final String? rows;

  const WLEDConfig({
    required this.ledCount,
    required this.mode,
    required this.build,
    required this.name,
    required this.mac,
    required this.rows,
  });
}
