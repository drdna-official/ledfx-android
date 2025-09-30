import 'dart:convert';
import 'dart:developer';
import 'dart:ui';

import 'package:ledfx/src/devices/device.dart';
import 'package:n_dimensional_array/domain/models/nd_array.dart';
import 'package:http/http.dart' as http;

enum WLEDSyncMode { udp, ddp, e131 }

class WLEDDevice extends NetworkedDevice {
  WLEDDevice({
    required super.name,
    required super.pixelCount,
    required super.ipAddr,
    super.fps,
    required this.syncMode,
    this.timeout = 1,

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
        name: name,
        pixelCount: pixelCount,
        ipAddr: ipAddr,
        port: 21324,
        timeout: timeout,
        udpPacketType: "DNRGB",
        minimizeTraffic: true,
        fps: fps,
      ),
      WLEDSyncMode.ddp => RealtimeUDPDevice(
        name: name,
        pixelCount: pixelCount,
        ipAddr: ipAddr,
        port: 21324,
        udpPacketType: "DNRGB",
        minimizeTraffic: true,
      ),
      WLEDSyncMode.e131 => RealtimeUDPDevice(
        name: name,
        pixelCount: pixelCount,
        ipAddr: ipAddr,
        port: 21324,
        udpPacketType: "DNRGB",
        minimizeTraffic: true,
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

  Future<void> getConfig() async {
    final configResp = await _requestGET("json/info");
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
  }
}
