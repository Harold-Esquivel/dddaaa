import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const String kServiceUUID = "12345678-1234-1234-1234-123456789abc";
const String kCharacteristicUUID = "12345678-1234-1234-1234-123456789abd";
const String kDeviceName = "BiometricSensor";

// ─────────────────────────────────────────────────────────────────────────────
// App Root
// ─────────────────────────────────────────────────────────────────────────────
void main() {
  runApp(const BiometricApp());
}

class BiometricApp extends StatelessWidget {
  const BiometricApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BiometricSensor BLE',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const ScanPage(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCAN PAGE
// ─────────────────────────────────────────────────────────────────────────────
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final Map<String, ScanResult> _devicesMap = {};
  StreamSubscription? _scanSub;
  StreamSubscription? _isScanSub;
  bool _scanning = false;

  List<ScanResult> get _devices {
    final list = _devicesMap.values.toList();
    // Primero el ESP32 objetivo, luego el resto por nombre
    list.sort((a, b) {
      final aIsTarget = a.device.platformName == kDeviceName;
      final bIsTarget = b.device.platformName == kDeviceName;
      if (aIsTarget && !bIsTarget) return -1;
      if (!aIsTarget && bIsTarget) return 1;
      // Ordenar por RSSI (más fuerte primero)
      return b.rssi.compareTo(a.rssi);
    });
    return list;
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _isScanSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    _devicesMap.clear();
    setState(() => _scanning = true);

    await _scanSub?.cancel();
    await _isScanSub?.cancel();

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      bool changed = false;
      for (final r in results) {
        final id = r.device.remoteId.toString();
        if (!_devicesMap.containsKey(id) || _devicesMap[id]!.rssi != r.rssi) {
          _devicesMap[id] = r;
          changed = true;
        }
      }
      if (changed && mounted) setState(() {});
    });

    _isScanSub = FlutterBluePlus.isScanning.listen((value) {
      if (mounted) setState(() => _scanning = value);
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 12),
        androidUsesFineLocation: true,
      );
    } catch (e) {
      debugPrint('Scan error: $e');
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  Future<void> _connect(BluetoothDevice device) async {
    await _stopScan();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DataPage(device: device)),
    );
  }

  // Convierte RSSI a icono de señal
  Widget _rssiIcon(int rssi) {
    IconData icon;
    Color color;
    if (rssi >= -60) {
      icon = Icons.signal_wifi_4_bar;
      color = Colors.greenAccent;
    } else if (rssi >= -75) {
      icon = Icons.network_wifi_3_bar;
      color = Colors.yellowAccent;
    } else if (rssi >= -85) {
      icon = Icons.network_wifi_2_bar;
      color = Colors.orangeAccent;
    } else {
      icon = Icons.network_wifi_1_bar;
      color = Colors.redAccent;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        Text('$rssi', style: TextStyle(fontSize: 10, color: color)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = _devices;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Row(
          children: [
            Icon(Icons.bluetooth, color: Colors.tealAccent),
            SizedBox(width: 8),
            Text(
              'ESP32 BLE Scanner',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          if (_scanning)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.tealAccent,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── BOTÓN ESCANEAR ────────────────────────────────────────────────
          Container(
            color: const Color(0xFF161B22),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _scanning
                          ? Colors.grey.shade800
                          : Colors.teal,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: Icon(_scanning ? Icons.radar : Icons.search),
                    label: Text(
                      _scanning ? 'Escaneando...' : 'Buscar dispositivos BLE',
                      style: const TextStyle(fontSize: 15),
                    ),
                    onPressed: _scanning ? null : _startScan,
                  ),
                ),
                if (_scanning) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _stopScan,
                    icon: const Icon(
                      Icons.stop_circle,
                      color: Colors.redAccent,
                      size: 30,
                    ),
                    tooltip: 'Detener',
                  ),
                ],
              ],
            ),
          ),

          // ── ESTADO / CONTADOR ─────────────────────────────────────────────
          if (devices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Text(
                    '${devices.length} dispositivo${devices.length != 1 ? 's' : ''} encontrado${devices.length != 1 ? 's' : ''}',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  ),
                ],
              ),
            ),

          // ── LISTA DE DISPOSITIVOS ─────────────────────────────────────────
          Expanded(
            child: devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bluetooth_searching,
                          size: 64,
                          color: Colors.grey.shade700,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _scanning
                              ? 'Buscando dispositivos cercanos...'
                              : 'Presiona "Buscar" para iniciar',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: devices.length,
                    itemBuilder: (_, i) {
                      final result = devices[i];
                      final name = result.device.platformName.isEmpty
                          ? 'Sin nombre'
                          : result.device.platformName;
                      final isTarget =
                          result.device.platformName == kDeviceName;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: isTarget
                              ? const Color(0xFF0D2818)
                              : const Color(0xFF1C2128),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _connect(result.device),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isTarget
                                      ? Colors.tealAccent.withOpacity(0.5)
                                      : Colors.white10,
                                  width: isTarget ? 1.5 : 1,
                                ),
                              ),
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  // Icono Bluetooth
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: isTarget
                                          ? Colors.teal.withOpacity(0.2)
                                          : Colors.white.withOpacity(0.05),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isTarget
                                          ? Icons.monitor_heart
                                          : Icons.bluetooth,
                                      color: isTarget
                                          ? Colors.tealAccent
                                          : Colors.grey.shade400,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Nombre + MAC
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              name,
                                              style: TextStyle(
                                                color: isTarget
                                                    ? Colors.tealAccent
                                                    : Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            if (isTarget) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.teal
                                                      .withOpacity(0.3),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'ESP32',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.tealAccent,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          result.device.remoteId.toString(),
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 12,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // RSSI
                                  _rssiIcon(result.rssi),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Colors.white30,
                                  ),
                                ],
                              ),
                            ),
                          ),
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

// ─────────────────────────────────────────────────────────────────────────────
// DATA PAGE — con reconexión automática
// ─────────────────────────────────────────────────────────────────────────────
class DataPage extends StatefulWidget {
  final BluetoothDevice device;
  const DataPage({super.key, required this.device});

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage>
    with SingleTickerProviderStateMixin {
  // Estado de conexión
  bool _connected = false;
  bool _connecting = false;
  bool _disposed = false;
  String _status = 'Conectando...';

  // Datos BLE
  String _rawData = '--';
  int _bpm = 0;
  String _state = 'WAITING';

  // Streams
  StreamSubscription? _notifySub;
  StreamSubscription? _connectionSub;

  // Reconexión
  static const int _maxRetries = 3;
  int _retries = 0;

  // Animación de pulso
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnim = Tween(
      begin: 1.0,
      end: 1.25,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));
    _connectToDevice();
  }

  @override
  void dispose() {
    _disposed = true;
    _pulseController.dispose();
    _notifySub?.cancel();
    _connectionSub?.cancel();
    widget.device.disconnect();
    super.dispose();
  }

  // ── CONEXIÓN PRINCIPAL ────────────────────────────────────────────────────
  Future<void> _connectToDevice() async {
    if (_disposed) return;
    _setStatus('Conectando...', connecting: true, connected: false);

    // Desconectar limpiamente si ya estaba conectado
    try {
      await _notifySub?.cancel();
      await _connectionSub?.cancel();
      await widget.device.disconnect();
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 400));
    if (_disposed) return;

    try {
      await widget.device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      if (_disposed) return;

      // Escuchar desconexiones
      _connectionSub = widget.device.connectionState.listen(
        _onConnectionStateChange,
      );

      // Descubrir servicios
      _setStatus(
        'Descubriendo servicios...',
        connecting: true,
        connected: false,
      );
      final services = await widget.device.discoverServices();

      BluetoothCharacteristic? targetChar;
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() == kServiceUUID) {
          for (final c in svc.characteristics) {
            if (c.uuid.toString().toLowerCase() == kCharacteristicUUID) {
              targetChar = c;
              break;
            }
          }
        }
        if (targetChar != null) break;
      }

      if (targetChar == null) {
        _setStatus(
          'Servicio BLE no encontrado\n(UUID no coincide)',
          connecting: false,
          connected: false,
        );
        return;
      }

      // Activar notificaciones
      await targetChar.setNotifyValue(true);
      _notifySub = targetChar.onValueReceived.listen(_onDataReceived);

      _retries = 0;
      _setStatus('Recibiendo datos', connecting: false, connected: true);
    } on FlutterBluePlusException catch (e) {
      debugPrint('BLE connect error: $e');
      _handleConnectionError(e.toString());
    } catch (e) {
      debugPrint('General error: $e');
      _handleConnectionError(e.toString());
    }
  }

  void _onConnectionStateChange(BluetoothConnectionState state) {
    if (_disposed) return;
    if (state == BluetoothConnectionState.disconnected && _connected) {
      _setStatus('Desconectado', connecting: false, connected: false);
      _autoReconnect();
    }
  }

  void _handleConnectionError(String error) {
    if (_disposed) return;
    _setStatus('Error: $error', connecting: false, connected: false);
    _autoReconnect();
  }

  void _autoReconnect() {
    if (_disposed || _retries >= _maxRetries) {
      if (!_disposed && _retries >= _maxRetries) {
        _setStatus(
          'No se pudo conectar\ndespués de $_maxRetries intentos',
          connecting: false,
          connected: false,
        );
      }
      return;
    }
    _retries++;
    _setStatus(
      'Reconectando (intento $_retries/$_maxRetries)...',
      connecting: true,
      connected: false,
    );
    Future.delayed(const Duration(seconds: 2), _connectToDevice);
  }

  void _setStatus(
    String msg, {
    required bool connecting,
    required bool connected,
  }) {
    if (_disposed || !mounted) return;
    setState(() {
      _status = msg;
      _connecting = connecting;
      _connected = connected;
    });
  }

  // ── DATOS BLE ─────────────────────────────────────────────────────────────
  void _onDataReceived(List<int> value) {
    final text = utf8.decode(value, allowMalformed: true);
    debugPrint('BLE DATA: $text');
    _parseData(text);
  }

  void _parseData(String raw) {
    int tempBpm = _bpm;
    String tempState = _state;

    for (final part in raw.split(',')) {
      final kv = part.split(':');
      if (kv.length != 2) continue;
      if (kv[0].trim() == 'BPM') {
        tempBpm = int.tryParse(kv[1].trim()) ?? tempBpm;
      }
      if (kv[0].trim() == 'STATE') {
        tempState = kv[1].trim();
      }
    }

    if (!_disposed && mounted) {
      setState(() {
        _bpm = tempBpm;
        _state = tempState;
        _rawData = raw;
      });
      // Animación de latido cuando cambia BPM
      if (tempBpm != _bpm) {
        _pulseController.forward(from: 0);
      }
    }
  }

  Future<void> _disconnect() async {
    _disposed = true;
    await _notifySub?.cancel();
    await _connectionSub?.cancel();
    try {
      await widget.device.disconnect();
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bool alert = _state == 'SOMNOLENCIA';
    final bool waiting = _state == 'WAITING';

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.device.platformName.isEmpty
                  ? 'Dispositivo BLE'
                  : widget.device.platformName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.device.remoteId.toString(),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _disconnect,
            icon: const Icon(Icons.bluetooth_disabled, color: Colors.redAccent),
            tooltip: 'Desconectar',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── STATUS ──────────────────────────────────────────────────────
            _StatusCard(
              connected: _connected,
              connecting: _connecting,
              status: _status,
            ),
            const SizedBox(height: 14),

            // ── BPM ─────────────────────────────────────────────────────────
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, child) {
                return Transform.scale(
                  scale: _connected ? _pulseAnim.value : 1.0,
                  child: child,
                );
              },
              child: _BpmCard(bpm: _bpm, connected: _connected),
            ),
            const SizedBox(height: 14),

            // ── ESTADO ──────────────────────────────────────────────────────
            _StateCard(state: _state, alert: alert, waiting: waiting),
            const SizedBox(height: 14),

            // ── RAW DATA ────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2128),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Datos RAW',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _rawData,
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            // ── BOTÓN RECONECTAR MANUAL ─────────────────────────────────────
            if (!_connected && !_connecting) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar conexión'),
                  onPressed: () {
                    _disposed = false;
                    _retries = 0;
                    _connectToDevice();
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS AUXILIARES
// ─────────────────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final bool connected;
  final bool connecting;
  final String status;

  const _StatusCard({
    required this.connected,
    required this.connecting,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    Color borderColor;
    Color iconColor;
    IconData icon;

    if (connected) {
      borderColor = Colors.tealAccent.withOpacity(0.5);
      iconColor = Colors.tealAccent;
      icon = Icons.check_circle;
    } else if (connecting) {
      borderColor = Colors.amber.withOpacity(0.4);
      iconColor = Colors.amber;
      icon = Icons.sync;
    } else {
      borderColor = Colors.redAccent.withOpacity(0.4);
      iconColor = Colors.redAccent;
      icon = Icons.error_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2128),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        children: [
          connecting
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: iconColor,
                  ),
                )
              : Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status,
              style: TextStyle(color: Colors.grey.shade300, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _BpmCard extends StatelessWidget {
  final int bpm;
  final bool connected;

  const _BpmCard({required this.bpm, required this.connected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2128),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: connected ? Colors.red.withOpacity(0.3) : Colors.white10,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.favorite,
            color: connected ? Colors.redAccent : Colors.grey,
            size: 52,
          ),
          const SizedBox(height: 10),
          Text(
            bpm > 0 ? '$bpm' : '--',
            style: TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.bold,
              color: connected ? Colors.white : Colors.grey,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'BPM',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 16,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  final String state;
  final bool alert;
  final bool waiting;

  const _StateCard({
    required this.state,
    required this.alert,
    required this.waiting,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color border;
    Color textColor;
    IconData icon;

    if (waiting) {
      bg = const Color(0xFF1C2128);
      border = Colors.white12;
      textColor = Colors.grey;
      icon = Icons.hourglass_empty;
    } else if (alert) {
      bg = Colors.red.shade900.withOpacity(0.4);
      border = Colors.redAccent.withOpacity(0.6);
      textColor = Colors.redAccent.shade100;
      icon = Icons.warning_amber_rounded;
    } else {
      bg = Colors.teal.shade900.withOpacity(0.3);
      border = Colors.tealAccent.withOpacity(0.4);
      textColor = Colors.tealAccent.shade100;
      icon = Icons.check_circle_outline;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Column(
        children: [
          Icon(icon, color: textColor, size: 48),
          const SizedBox(height: 10),
          Text(
            state,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: textColor,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}
