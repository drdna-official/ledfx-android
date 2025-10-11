// ignore_for_file: constant_identifier_names

import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:ledfx/src/core.dart';

sealed class LEDFxEvent {
  static const CORE_SHUTDOWN = 'shutdown';
  static const DEVICE_CREATED = 'device_created';
  static const DEVICES_UPDATED = 'devices_updated';
  static const DEVICE_UPDATE = 'device_update';
  static const VIRTUAL_UPDATE = 'virtual_update';
  static const VIRTUAL_PAUSED = 'virtual_paused';
  static const VISUALISATION_UPDATE = "visualisation_update";

  final String eventType;
  const LEDFxEvent(this.eventType);

  Map<String, dynamic> toMap();
}

class LEDFxEventListener {
  const LEDFxEventListener(this.callback, [this.filter = const {}]);
  final void Function(LEDFxEvent) callback;
  final Map filter;

  bool filterEvent(LEDFxEvent event) {
    final eventPropertyMap = event.toMap();
    for (final k in filter.keys) {
      if (eventPropertyMap[k] != filter[k]) {
        return true;
      }
    }
    return false;
  }
}

class LEDFxEvents {
  final LEDFx ledfx;
  LEDFxEvents(this.ledfx) : _listeners = {};

  Map<String, List<LEDFxEventListener>> _listeners;

  void fireEvent(LEDFxEvent event) {
    final listeners = _listeners[event.eventType] ?? [];
    if (listeners.isEmpty) return;

    for (final listener in listeners) {
      if (!listener.filterEvent(event)) {
        listener.callback(event);
      }
    }
  }

  Future<VoidCallback> addListener(
    void Function(LEDFxEvent) callback,
    String eventType, [
    Map filter = const {},
  ]) async {
    final listener = LEDFxEventListener(callback, filter);

    if (_listeners.keys.contains(eventType)) {
      _listeners[eventType]!.add(listener);
    } else {
      _listeners[eventType] = [listener];
    }

    void removeListener() {
      _removeListener(eventType, listener);
    }

    return removeListener;
  }

  void _removeListener(String eventType, LEDFxEventListener listener) {
    if (_listeners.keys.contains(eventType)) {
      _listeners[eventType]!.remove(listener);
      if (_listeners[eventType]!.isEmpty) _listeners.remove(eventType);
    }
  }
}

class VirtualPauseEvent extends LEDFxEvent {
  final String id;
  const VirtualPauseEvent(this.id) : super(LEDFxEvent.VIRTUAL_PAUSED);

  @override
  Map<String, dynamic> toMap() {
    return {"eventType": eventType, "id": id};
  }
}

class DeviceCreatedEvent extends LEDFxEvent {
  final String name;
  const DeviceCreatedEvent(this.name) : super(LEDFxEvent.DEVICE_CREATED);

  @override
  Map<String, dynamic> toMap() {
    return {"eventType": eventType, "name": name};
  }
}

class DevicesUpdatedEvent extends LEDFxEvent {
  final String deviceID;
  const DevicesUpdatedEvent(this.deviceID) : super(LEDFxEvent.DEVICES_UPDATED);
  @override
  Map<String, dynamic> toMap() {
    return {"eventType": eventType, "deviceID": deviceID};
  }
}

class DeviceUpdateEvent extends LEDFxEvent {
  final String deviceID;
  final List<Float64List> pixels;
  const DeviceUpdateEvent(this.deviceID, this.pixels)
    : super(LEDFxEvent.DEVICE_UPDATE);

  @override
  Map<String, dynamic> toMap() {
    return {"eventType": eventType, "deviceID": deviceID, "pixels": pixels};
  }
}

class VirtualUpdateEvent extends LEDFxEvent {
  final String virtualID;
  final List<Float64List> pixels;
  const VirtualUpdateEvent(this.virtualID, this.pixels)
    : super(LEDFxEvent.VIRTUAL_UPDATE);
  @override
  Map<String, dynamic> toMap() {
    return {"eventType": eventType, "virtualID": virtualID, "pixels": pixels};
  }
}

class VisualisationUpdateEvent extends LEDFxEvent {
  final bool isDevice;
  final String visID;
  final List<Float64List> pixels;
  final List<int> shape;

  VisualisationUpdateEvent(this.visID, this.pixels, this.shape, this.isDevice)
    : super(LEDFxEvent.VISUALISATION_UPDATE);

  @override
  Map<String, dynamic> toMap() {
    return {
      "eventType": eventType,
      "visID": visID,
      "pixels": pixels,
      "shape": shape,
      "isDevice": isDevice,
    };
  }
}
