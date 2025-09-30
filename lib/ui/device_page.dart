import 'package:flutter/material.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return DeviceAddDialogue();
            },
          );
        },
      ),
    );
  }
}

class DeviceAddDialogue extends StatefulWidget {
  const DeviceAddDialogue({super.key});

  @override
  State<DeviceAddDialogue> createState() => _DeviceAddDialogueState();
}

enum DeviceType {
  wled('WLED');

  const DeviceType(this.label);
  final String label;

  String getLabel() => label;
}

class _DeviceAddDialogueState extends State<DeviceAddDialogue> {
  DeviceType? selectedDeviceType;
  TextEditingController ipaddress = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Add New Device'),
        DropdownButton(
          value: selectedDeviceType,
          hint: Text("Select Device Type"),
          items: DeviceType.values
              .map((e) => DropdownMenuItem(value: e, child: Text(e.getLabel())))
              .toList(),
          onChanged: (DeviceType? selected) {
            setState(() {
              selectedDeviceType = selected;
            });
          },
        ),

        switch (selectedDeviceType) {
          DeviceType.wled => Column(
            children: [
              TextFormField(
                controller: ipaddress,
                decoration: InputDecoration(
                  hintText: "Enter Address of WLED Device",
                ),
              ),
            ],
          ),
          _ => const SizedBox.shrink(),
        },

        OutlinedButton(onPressed: () {}, child: Text("Add Device")),
      ],
    );
  }
}
