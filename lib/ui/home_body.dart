import 'package:flutter/material.dart';
import 'package:ledfx/src/core.dart';
import 'package:ledfx/src/devices/device.dart';
import 'package:ledfx/src/effects/effect.dart';
import 'package:ledfx/src/effects/temporal.dart';
import 'package:ledfx/src/virtual.dart';

class HomeBody extends StatefulWidget {
  final LEDFx ledfx;
  const HomeBody({super.key, required this.ledfx});

  @override
  State<HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<HomeBody> {
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

          ListView(
            shrinkWrap: true,
            children: widget.ledfx.config.virtuals.map((v) {
              final config = v["config"] as VirtualConfig;
              final virtual = widget.ledfx.virtuals.virtuals[v["id"]];

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
                    ],
                  ),
                ),
                trailing: ElevatedButton.icon(
                  onPressed: () {
                    final virtual = widget.ledfx.virtuals.virtuals[v["id"]];
                    if (virtual != null) {
                      virtual.setEffect(
                        RainbowEffect(
                          ledfx: widget.ledfx,
                          config: EffectConfig(name: "Rainbow Effect"),
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
  TextEditingController _address = TextEditingController();
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
                        validator: (value) {
                          if (value != "wled") {
                            return 'Supported - wled';
                          }
                          return null;
                        },
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
                              await widget.ledfx.devices.addNewDevice(
                                DeviceConfig(
                                  pixelCount: 200,
                                  rgbwLED: false,
                                  name: "WLED Test",
                                  type: _type.text,
                                  address: _address.text,
                                ),
                              );
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
