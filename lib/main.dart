import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: BluetoothPage(),
    );
  }
}

class BluetoothPage extends StatefulWidget {
  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {

  List<ScanResult> devices = [];

  BluetoothDevice? connectedDevice;

  BluetoothCharacteristic? characteristic;

  final TextEditingController controller =
      TextEditingController();

  String messages = "";

  @override
  void initState() {
    super.initState();
    scanDevices();
  }

  void scanDevices() async {

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    FlutterBluePlus.scanResults.listen((results) {

      setState(() {
        devices = results;
      });
    });
  }

  Future<void> connect(BluetoothDevice device) async {

    await device.connect();

    connectedDevice = device;

    List<BluetoothService> services =
        await device.discoverServices();

    for (BluetoothService service in services) {

      for (BluetoothCharacteristic c
          in service.characteristics) {

        characteristic = c;
      }
    }

    setState(() {});
  }

  Future<void> sendMessage() async {

    if (characteristic != null) {

      await characteristic!
          .write(utf8.encode(controller.text));

      setState(() {
        messages +=
            "\nYo: ${controller.text}";
      });

      controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text("ESP32 BLE"),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(

          children: [

            Expanded(
              child: ListView.builder(

                itemCount: devices.length,

                itemBuilder: (context, index) {

                  final device = devices[index].device;

                  return Card(

                    child: ListTile(

                      title: Text(
                        device.platformName.isEmpty
                            ? "Sin nombre"
                            : device.platformName,
                      ),

                      subtitle: Text(device.remoteId.str),

                      trailing: ElevatedButton(

                        onPressed: () {
                          connect(device);
                        },

                        child: const Text("Conectar"),
                      ),
                    ),
                  );
                },
              ),
            ),

            TextField(
              controller: controller,

              decoration: const InputDecoration(
                hintText: "Mensaje",
              ),
            ),

            ElevatedButton(
              onPressed: sendMessage,
              child: const Text("Enviar"),
            ),

            Expanded(
              child: SingleChildScrollView(
                child: Text(messages),
              ),
            )
          ],
        ),
      ),
    );
  }
}