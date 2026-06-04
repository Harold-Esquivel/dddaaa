/*
 * ============================================================
 *  Flutter App — Cliente BLE
 *  Se conecta al ESP32 "BiometricSensor" y recibe datos
 *
 *  Dependencias (pubspec.yaml):
 *    flutter_blue_plus: ^1.32.0
 *
 *  Permisos:
 *    Android: ACCESS_FINE_LOCATION, BLUETOOTH_SCAN, BLUETOOTH_CONNECT
 *    iOS:     NSBluetoothAlwaysUsageDescription en Info.plist
 *
 *  Reemplaza el contenido de lib/main.dart con este archivo.
 * ============================================================
 */

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// ── UUIDs (deben coincidir con el ESP32) ────────────────────
const String kServiceUUID        = "12345678-1234-1234-1234-123456789abc";
const String kCharacteristicUUID = "12345678-1234-1234-1234-123456789abd";
const String kDeviceName         = "BiometricSensor";

// ────────────────────────────────────────────────────────────
void main() => runApp(const BiometricApp());

class BiometricApp extends StatelessWidget {
  const BiometricApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BiometricSensor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const ScanPage(),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  PANTALLA DE ESCANEO
// ═══════════════════════════════════════════════════════════
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final List<ScanResult> _results = [];
  bool _isScanning = false;
  StreamSubscription? _scanSub;

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  // ── Iniciar escaneo ────────────────────────────────────
  void _startScan() async {
    setState(() {
      _results.clear();
      _isScanning = true;
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (!_results.any((e) => e.device.remoteId == r.device.remoteId)) {
          setState(() => _results.add(r));
        }
      }
    });

    FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning && mounted) setState(() => _isScanning = false);
    });
  }

  // ── Conectar al dispositivo seleccionado ───────────────
  void _connect(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DataPage(device: device),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscar BiometricSensor'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Column(
        children: [
          // ── Botón de escaneo ─────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isScanning ? null : _startScan,
                icon: _isScanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.bluetooth_searching),
                label: Text(_isScanning ? 'Escaneando...' : 'Escanear'),
              ),
            ),
          ),

          // ── Lista de dispositivos ────────────────────
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (ctx, i) {
                final r = _results[i];
                final name = r.device.platformName.isEmpty
                    ? 'Desconocido'
                    : r.device.platformName;
                final isTarget = name == kDeviceName;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  elevation: isTarget ? 3 : 0,
                  color: isTarget
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  child: ListTile(
                    leading: Icon(
                      Icons.bluetooth,
                      color: isTarget ? Colors.teal : Colors.grey,
                    ),
                    title: Text(name,
                        style: TextStyle(
                            fontWeight: isTarget ? FontWeight.bold : FontWeight.normal)),
                    subtitle: Text(r.device.remoteId.toString()),
                    trailing: Text('${r.rssi} dBm',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    onTap: () => _connect(r.device),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  PANTALLA DE DATOS EN TIEMPO REAL
// ═══════════════════════════════════════════════════════════
class DataPage extends StatefulWidget {
  final BluetoothDevice device;
  const DataPage({super.key, required this.device});

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  // ── Estado de conexión ─────────────────────────────────
  String _status        = 'Conectando...';
  bool   _connected     = false;

  // ── Datos biométricos parseados ───────────────────────
  int    _bpm           = 0;
  double _spo2          = 0;
  double _ax = 0, _ay = 0, _az = 0;
  double _gx = 0, _gy = 0, _gz = 0;
  String _rawData       = '--';

  StreamSubscription? _connectionSub;
  StreamSubscription? _notifySub;

  @override
  void initState() {
    super.initState();
    _connectAndSubscribe();
  }

  // ── Conectar y suscribirse a notificaciones ─────────
  Future<void> _connectAndSubscribe() async {
    try {
      await widget.device.connect(timeout: const Duration(seconds: 15));
      setState(() => _status = 'Conectado ✓');

      // Observar desconexiones
      _connectionSub = widget.device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && mounted) {
          setState(() {
            _connected = false;
            _status = 'Desconectado';
          });
        }
      });

      // Descubrir servicios
      List<BluetoothService> services = await widget.device.discoverServices();

      for (BluetoothService service in services) {
        if (service.uuid.toString().toLowerCase() == kServiceUUID) {
          for (BluetoothCharacteristic c in service.characteristics) {
            if (c.uuid.toString().toLowerCase() == kCharacteristicUUID) {
              // Activar notificaciones
              await c.setNotifyValue(true);

              _notifySub = c.onValueReceived.listen((value) {
                final text = utf8.decode(value);
                _parseData(text);
              });

              setState(() {
                _connected = true;
                _status    = 'Recibiendo datos ▶';
              });
              return;
            }
          }
        }
      }

      setState(() => _status = 'Error: servicio no encontrado');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  // ── Parsear CSV del ESP32 ────────────────────────────
  // Formato: BPM:72,SPO2:98.5,AX:-0.12,AY:0.04,AZ:9.81,GX:0.01,GY:-0.02,GZ:0.00
  void _parseData(String raw) {
    setState(() => _rawData = raw);
    try {
      final Map<String, double> fields = {};
      for (final part in raw.split(',')) {
        final kv = part.split(':');
        if (kv.length == 2) {
          fields[kv[0].trim()] = double.tryParse(kv[1].trim()) ?? 0;
        }
      }
      setState(() {
        _bpm  = fields['BPM']?.toInt() ?? _bpm;
        _spo2 = fields['SPO2'] ?? _spo2;
        _ax   = fields['AX']   ?? _ax;
        _ay   = fields['AY']   ?? _ay;
        _az   = fields['AZ']   ?? _az;
        _gx   = fields['GX']   ?? _gx;
        _gy   = fields['GY']   ?? _gy;
        _gz   = fields['GZ']   ?? _gz;
      });
    } catch (_) {}
  }

  // ── Desconectar limpiamente ──────────────────────────
  Future<void> _disconnect() async {
    await _notifySub?.cancel();
    await _connectionSub?.cancel();
    await widget.device.disconnect();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _notifySub?.cancel();
    _connectionSub?.cancel();
    widget.device.disconnect();
    super.dispose();
  }

  // ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.platformName.isEmpty
            ? 'BiometricSensor'
            : widget.device.platformName),
        backgroundColor: cs.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth_disabled),
            tooltip: 'Desconectar',
            onPressed: _disconnect,
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Estado ──────────────────────────────
            _StatusChip(status: _status, connected: _connected),
            const SizedBox(height: 20),

            // ── Pulsómetro / SpO2 ───────────────────
            Row(children: [
              Expanded(child: _BigMetricCard(
                icon: Icons.favorite,
                color: Colors.red,
                label: 'Frec. Cardíaca',
                value: '$_bpm',
                unit: 'BPM',
              )),
              const SizedBox(width: 12),
              Expanded(child: _BigMetricCard(
                icon: Icons.air,
                color: Colors.blue,
                label: 'SpO₂',
                value: _spo2.toStringAsFixed(1),
                unit: '%',
              )),
            ]),
            const SizedBox(height: 12),

            // ── Acelerómetro ─────────────────────────
            _SensorSection(
              title: 'Acelerómetro (m/s²)',
              icon: Icons.speed,
              rows: [
                ('X', _ax), ('Y', _ay), ('Z', _az),
              ],
            ),
            const SizedBox(height: 12),

            // ── Giroscopio ───────────────────────────
            _SensorSection(
              title: 'Giroscopio (rad/s)',
              icon: Icons.rotate_90_degrees_ccw,
              rows: [
                ('X', _gx), ('Y', _gy), ('Z', _gz),
              ],
            ),
            const SizedBox(height: 12),

            // ── Datos crudos ──────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Último paquete raw',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    Text(_rawData,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  WIDGETS AUXILIARES
// ═══════════════════════════════════════════════════════════

class _StatusChip extends StatelessWidget {
  final String status;
  final bool connected;
  const _StatusChip({required this.status, required this.connected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: connected ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: connected ? Colors.green.shade200 : Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(connected ? Icons.check_circle : Icons.hourglass_top,
              size: 16,
              color: connected ? Colors.green : Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(status,
                style: TextStyle(
                    color: connected ? Colors.green.shade700 : Colors.orange.shade700,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _BigMetricCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String unit;

  const _BigMetricCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(unit, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 4),
            Text(label,
                style:
                    const TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _SensorSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<(String, double)> rows;

  const _SensorSection(
      {required this.title, required this.icon, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            const Divider(height: 16),
            ...rows.map((row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 20,
                          child: Text(row.$1,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: ((row.$2 + 20) / 40).clamp(0, 1),
                          backgroundColor: Colors.grey.shade200,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 64,
                        child: Text(
                          row.$2.toStringAsFixed(3),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
