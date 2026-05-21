import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vibration/vibration.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const BluetoothPage(),
    );
  }
}

class BluetoothPage extends StatefulWidget {
  const BluetoothPage({super.key});

  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  List<ScanResult> dispositivos = [];
  bool buscando = true;

  @override
  void initState() {
    super.initState();
    buscarDispositivos();
  }

  void buscarDispositivos() async {
    try {
      if (await FlutterBluePlus.isSupported == false) {
        print("Bluetooth no soportado");
        return;
      }

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
      );

      FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          dispositivos = results
              .where((r) => r.device.name.isNotEmpty)
              .toList();
        });
      });

      FlutterBluePlus.isScanning.listen((isScanning) {
        if (!isScanning) {
          setState(() {
            buscando = false;
          });
        }
      });
    } catch (e) {
      print("Error en búsqueda: $e");
      setState(() {
        buscando = false;
      });
    }
  }

  Future<void> conectar(BluetoothDevice device) async {
    try {
      await device.connect();

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(
            device: device,
            nombre: device.name.isNotEmpty ? device.name : "Dispositivo",
          ),
        ),
      );
    } catch (e) {
      print("Error al conectar: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error al conectar")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F111A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Bluetooth"),
      ),
      body: buscando
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : dispositivos.isEmpty
              ? const Center(
                  child: Text("No se encontraron dispositivos"),
                )
              : ListView.builder(
                  itemCount: dispositivos.length,
                  itemBuilder: (_, index) {
                    BluetoothDevice device = dispositivos[index].device;

                    return Container(
                      margin: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: ListTile(
                        title: Text(
                          device.name.isNotEmpty
                              ? device.name
                              : "Sin nombre",
                        ),
                        subtitle: Text(
                          device.remoteId.str,
                        ),
                        trailing: ElevatedButton(
                          onPressed: () {
                            conectar(device);
                          },
                          child: const Text("Conectar"),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    super.dispose();
  }
}

class HomePage extends StatefulWidget {
  final BluetoothDevice device;
  final String nombre;

  const HomePage({
    super.key,
    required this.device,
    required this.nombre,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {

  String estado = "CONECTADO";

  double pitch = 0;
  double roll = 0;

  int golpes = 0;

  bool mostrarAlerta = false;

  DateTime ultimoGolpe = DateTime.now();

  late AnimationController controller;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    escucharDatos();
  }

  void escucharDatos() async {
    try {
      List<BluetoothService> services = await widget.device.discoverServices();

      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.notify) {
            await characteristic.setNotifyValue(true);

            characteristic.onValueReceived.listen((data) {
              try {
                String recibido = ascii.decode(data).trim();
                procesarDatos(recibido);
              } catch (e) {
                print("Error decodificando: $e");
              }
            });
          }
        }
      }
    } catch (e) {
      print("Error en escucha: $e");
    }
  }

  void procesarDatos(String data) {
    try {
      List<String> valores = data.split(',');

      if (valores.length < 3) return;

      double ax = double.tryParse(valores[0]) ?? 0;
      double ay = double.tryParse(valores[1]) ?? 0;
      double az = double.tryParse(valores[2]) ?? 0;

      pitch = atan2(ax, sqrt(ay * ay + az * az)) * 180 / pi;

      roll = atan2(ay, sqrt(ax * ax + az * az)) * 180 / pi;

      setState(() {});

      detectarMovimientoBrusco(ax, ay, az);
    } catch (e) {
      print("Error procesando datos: $e");
    }
  }

  void detectarMovimientoBrusco(
    double ax,
    double ay,
    double az,
  ) async {
    double fuerza = sqrt(ax * ax + ay * ay + az * az);

    if (fuerza > 25000) {
      DateTime ahora = DateTime.now();

      if (ahora.difference(ultimoGolpe).inMilliseconds > 800) {
        ultimoGolpe = ahora;

        golpes++;

        if (golpes == 3) {
          setState(() {
            mostrarAlerta = true;
          });

          if (await Vibration.hasVibrator() ?? false) {
            Vibration.vibrate(
              duration: 1500,
            );
          }

          Future.delayed(
            const Duration(seconds: 4),
            () {
              if (mounted) {
                setState(() {
                  mostrarAlerta = false;
                  golpes = 0;
                });
              }
            },
          );
        }
      }
    }
  }

  Widget tarjeta(
      String titulo,
      double valor,
      ) {

    return Container(

      width: 150,

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(

        color: Colors.white.withOpacity(0.06),

        borderRadius: BorderRadius.circular(25),

        border: Border.all(
          color: Colors.white24,
        ),
      ),

      child: Column(
        children: [

          Text(
            titulo,

            style: const TextStyle(
              fontSize: 20,
              color: Colors.white70,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            valor.toStringAsFixed(1),

            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.bold,
            ),
          ),

          const Text(
            "°",

            style: TextStyle(
              fontSize: 18,
              color: Colors.white70,
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: const Color(0xFF0F111A),

      body: SafeArea(

        child: Padding(

          padding: const EdgeInsets.all(25),

          child: Column(

            children: [

              const SizedBox(height: 30),

              Text(
                widget.nombre,

                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 15),

              Container(

                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),

                decoration: BoxDecoration(

                  color: Colors.green.withOpacity(0.2),

                  borderRadius: BorderRadius.circular(30),
                ),

                child: const Text(

                  "CONECTADO",

                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 60),

              Row(

                mainAxisAlignment:
                MainAxisAlignment.spaceEvenly,

                children: [

                  tarjeta(
                    "Pitch",
                    pitch,
                  ),

                  tarjeta(
                    "Roll",
                    roll,
                  ),
                ],
              ),

              const SizedBox(height: 60),

              Text(

                'Movimientos bruscos: $golpes/3',

                style: const TextStyle(
                  fontSize: 20,
                  color: Colors.white70,
                ),
              ),

              const Spacer(),

              if (mostrarAlerta)

                FadeTransition(

                  opacity: controller,

                  child: Container(

                    padding: const EdgeInsets.all(25),

                    width: double.infinity,

                    decoration: BoxDecoration(

                      borderRadius:
                      BorderRadius.circular(30),

                      color: Colors.redAccent
                          .withOpacity(0.2),

                      border: Border.all(
                        color: Colors.redAccent,
                        width: 2,
                      ),
                    ),

                    child: const Center(

                      child: Text(

                        'DESPIERTA',

                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    widget.device.disconnect();
    super.dispose();
  }
}