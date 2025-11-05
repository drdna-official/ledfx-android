import 'package:flutter/material.dart';
import 'package:ledfx/src/core.dart';
import 'package:ledfx/src/devices/device.dart';
import 'package:ledfx/src/effects/audio.dart';
import 'package:ledfx/src/effects/effect.dart';
import 'package:ledfx/src/effects/wavelength.dart';
import 'package:ledfx/src/virtual.dart';
import 'package:ledfx/visualizer/visualizer_painter.dart';
import 'package:permission_handler/permission_handler.dart';

final ValueNotifier<List<int>> rgb = ValueNotifier([]);

Future<bool> requestNotificationPermission() async {
  if (await Permission.notification.isGranted) return true;
  final status = await Permission.notification.request();
  return status.isGranted;
}

class HomeBody extends StatefulWidget {
  final LEDFx ledfx;
  const HomeBody({super.key, required this.ledfx});

  @override
  State<HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<HomeBody> {
  bool _deviceOn = false;

  @override
  void initState() {
    super.initState();
    widget.ledfx.audio = AudioAnalysisSource(ledfx: widget.ledfx);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: _showFormDialog,
                label: Text("Add Device"),
                icon: Icon(Icons.add),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {});
                },
                label: Text("Refresh"),
              ),
            ],
          ),
          Row(
            children: [
              Text("Current Selected Device"),
              if (widget.ledfx.audio?.audioDevices != null &&
                  widget.ledfx.audio!.audioDevices!.isNotEmpty)
                Text(
                  widget
                      .ledfx
                      .audio!
                      .audioDevices![widget.ledfx.audio!.activeAudioDeviceIndex]
                      .name,
                ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  widget.ledfx.audio!.startAudioCapture();
                },
                label: Text("Start Audio Capture"),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  widget.ledfx.audio!.stopAudioCapture();
                },
                label: Text("Stop Audio Capture"),
              ),
            ],
          ),
          SizedBox(
            height: 50,
            child: ValueListenableBuilder(
              valueListenable: rgb,
              builder: (BuildContext context, List<int> value, Widget? child) {
                return CustomPaint(
                  painter: VisualizerPainter(rgb: value, ledCount: 300),
                  size: const Size(double.infinity, 50),
                );
              },
            ),
          ),

          ListView(
            shrinkWrap: true,
            children: widget.ledfx.config.virtuals.map((v) {
              final config = v["config"] as VirtualConfig;
              final Virtual? virtual = widget.ledfx.virtuals.virtuals[v["id"]];
              final device = widget.ledfx.devices.devices[v["deviceID"]];

              final effectName =
                  (virtual != null && virtual.activeEffect != null)
                  ? virtual.activeEffect!.name
                  : "";

              return ListTile(
                title: Text(config.name),
                subtitle: Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("ID: ${config.deviceID}"),
                      Text("virtual ID: ${v["id"]}"),
                      Text("effect: $effectName"),
                      Switch(
                        value: virtual?.active ?? _deviceOn,
                        onChanged: (bool newVal) {
                          if (virtual == null) return;

                          setState(() {
                            _deviceOn = newVal;
                            _deviceOn
                                ? virtual.activate()
                                : virtual.deactivate();
                          });
                        },
                      ),
                    ],
                  ),
                ),
                trailing: ElevatedButton.icon(
                  onPressed: () {
                    final virtual = widget.ledfx.virtuals.virtuals[v["id"]];
                    if (virtual != null) {
                      virtual.setEffect(
                        WavelengthEffect(
                          ledfx: widget.ledfx,
                          config: EffectConfig(
                            name: "wavelength",
                            mirror: true,
                            blur: 3.0,
                          ),
                        ),
                      );
                      setState(() {});
                    }
                  },
                  label: Text("Add Effect"),
                  icon: Icon(Icons.add),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // Global key to uniquely identify the Form and enable validation
  final _formKey = GlobalKey<FormState>();

  // The maximum desired width for the dialogue card on large screens
  static const double _cardMaxWidth = 500.0;
  TextEditingController _address = TextEditingController(text: "192.168.0.160");
  TextEditingController _type = TextEditingController(text: "wled");
  // Function to show the custom dialogue
  void _showFormDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // The Center widget ensures the dialogue is centered on the screen.
        return Center(
          // ConstrainedBox enforces the maximum width for the dialogue content.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _cardMaxWidth),
            child: Dialog(
              // The Dialog widget provides the raised, card-like appearance
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(30.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    // Make sure the dialogue only takes the space its children need
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Text(
                        'Add New Device',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),

                      // Device Type Field
                      TextFormField(
                        controller: _type,
                        decoration: const InputDecoration(
                          labelText: 'DeviceType',
                          border: OutlineInputBorder(),
                        ),
                        // validator: (value) {
                        //   if (value == "wled" || value == "dummy") {
                        //     return null;
                        //   }
                        //   return 'Supported - wled / dummy';
                        // },
                      ),
                      const SizedBox(height: 15),
                      // Address Field
                      TextFormField(
                        controller: _address,
                        decoration: const InputDecoration(
                          labelText: 'Address',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 15),

                      // Submit Button
                      ElevatedButton(
                        onPressed: () async {
                          if (_formKey.currentState!.validate()) {
                            try {
                              final config = (_type.text == "wled")
                                  ? DeviceConfig(
                                      pixelCount: 200,
                                      rgbwLED: false,
                                      name: "WLED Test",
                                      type: _type.text,
                                      address: _address.text,
                                    )
                                  : DeviceConfig(
                                      pixelCount: 300,
                                      rgbwLED: false,
                                      name: "Dummy",
                                      type: _type.text,
                                      address: _address.text,
                                    );

                              await widget.ledfx.devices.addNewDevice(config);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Added New Device")),
                              );
                              Navigator.of(context).pop();
                              setState(() {});
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("Error - ${e.toString()}"),
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        child: const Text('Register'),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
