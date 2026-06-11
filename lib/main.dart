import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

// ─── BLE ──────────────────────────────────────────────────────────────────────
const String kServiceUUID        = "12345678-1234-1234-1234-123456789abc";
const String kCharacteristicUUID = "12345678-1234-1234-1234-123456789abd";
const String kDeviceName         = "BiometricSensor";

// ─── Serial ───────────────────────────────────────────────────────────────────
const int kBaudRate = 115200;

// ─────────────────────────────────────────────────────────────────────────────
void main() => runApp(const BiometricApp());

class BiometricApp extends StatelessWidget {
  const BiometricApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BiometricSensor',
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
    list.sort((a, b) {
      final aIsTarget = a.device.platformName == kDeviceName;
      final bIsTarget = b.device.platformName == kDeviceName;
      if (aIsTarget && !bIsTarget) return -1;
      if (!aIsTarget && bIsTarget) return 1;
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

  Future<void> _stopScan() async => FlutterBluePlus.stopScan();

  Future<void> _connect(BluetoothDevice device) async {
    await _stopScan();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DataPage(device: device)),
    );
  }

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

  void _openArduinoPage() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ArduinoPage()),
      );

  @override
  Widget build(BuildContext context) {
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
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _openArduinoPage,
            icon: const Icon(Icons.usb, color: Colors.orangeAccent),
            tooltip: 'Arduino Micro / MPU6050',
          ),
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
                      backgroundColor:
                          _scanning ? Colors.grey.shade800 : Colors.teal,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: Icon(_scanning ? Icons.radar : Icons.search),
                    label: Text(
                      _scanning
                          ? 'Escaneando...'
                          : 'Buscar dispositivos BLE',
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

          // ── CONTADOR ─────────────────────────────────────────────────────
          if (devices.isNotEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Text(
                    '${devices.length} dispositivo${devices.length != 1 ? 's' : ''} encontrado${devices.length != 1 ? 's' : ''}',
                    style:
                        TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  ),
                ],
              ),
            ),

          // ── LISTA ─────────────────────────────────────────────────────────
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
                        const SizedBox(height: 32),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orangeAccent,
                            side: const BorderSide(
                                color: Colors.orangeAccent, width: 1),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                          icon: const Icon(Icons.usb),
                          label: const Text('Arduino Micro / MPU6050 (USB)'),
                          onPressed: _openArduinoPage,
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: devices.length,
                          itemBuilder: (_, i) {
                            final result = devices[i];
                            final name =
                                result.device.platformName.isEmpty
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
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isTarget
                                            ? Colors.tealAccent
                                                .withOpacity(0.5)
                                            : Colors.white10,
                                        width: isTarget ? 1.5 : 1,
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(14),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: isTarget
                                                ? Colors.teal
                                                    .withOpacity(0.2)
                                                : Colors.white
                                                    .withOpacity(0.05),
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
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                  if (isTarget) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                      decoration:
                                                          BoxDecoration(
                                                        color: Colors.teal
                                                            .withOpacity(0.3),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                      ),
                                                      child: const Text(
                                                        'ESP32',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color: Colors
                                                              .tealAccent,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                result.device.remoteId
                                                    .toString(),
                                                style: TextStyle(
                                                  color:
                                                      Colors.grey.shade500,
                                                  fontSize: 12,
                                                  fontFamily: 'monospace',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
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
                      // Acceso rápido Arduino Micro
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orangeAccent,
                            side: const BorderSide(
                                color: Colors.orangeAccent, width: 1),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.usb),
                          label: const Text(
                              'Arduino Micro / MPU6050 (USB)'),
                          onPressed: _openArduinoPage,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA PAGE — ESP32 BLE (reconexión automática)
// ─────────────────────────────────────────────────────────────────────────────
class DataPage extends StatefulWidget {
  final BluetoothDevice device;
  const DataPage({super.key, required this.device});

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage>
    with SingleTickerProviderStateMixin {
  bool _connected  = false;
  bool _connecting = false;
  bool _disposed   = false;
  String _status   = 'Conectando...';

  String _rawData = '--';
  int    _bpm     = 0;
  String _state   = 'WAITING';

  StreamSubscription? _notifySub;
  StreamSubscription? _connectionSub;

  static const int _maxRetries = 3;
  int _retries = 0;

  late AnimationController _pulseController;
  late Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnim = Tween(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
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

  Future<void> _connectToDevice() async {
    if (_disposed) return;
    _setStatus('Conectando...', connecting: true, connected: false);

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

      _connectionSub = widget.device.connectionState.listen(
        _onConnectionStateChange,
      );

      _setStatus('Descubriendo servicios...', connecting: true, connected: false);
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

  void _setStatus(String msg, {required bool connecting, required bool connected}) {
    if (_disposed || !mounted) return;
    setState(() {
      _status     = msg;
      _connecting = connecting;
      _connected  = connected;
    });
  }

  void _onDataReceived(List<int> value) {
    final text = utf8.decode(value, allowMalformed: true);
    debugPrint('BLE DATA: $text');
    _parseData(text);
  }

  void _parseData(String raw) {
    int    tempBpm   = _bpm;
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
        _bpm     = tempBpm;
        _state   = tempState;
        _rawData = raw;
      });
      if (tempBpm != _bpm) _pulseController.forward(from: 0);
    }
  }

  Future<void> _disconnect() async {
    _disposed = true;
    await _notifySub?.cancel();
    await _connectionSub?.cancel();
    try { await widget.device.disconnect(); } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bool alert   = _state == 'SOMNOLENCIA';
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
                  color: Colors.white, fontWeight: FontWeight.bold),
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
            icon: const Icon(Icons.bluetooth_disabled,
                color: Colors.redAccent),
            tooltip: 'Desconectar',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _StatusCard(
              connected: _connected,
              connecting: _connecting,
              status: _status,
            ),
            const SizedBox(height: 14),

            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, child) => Transform.scale(
                scale: _connected ? _pulseAnim.value : 1.0,
                child: child,
              ),
              child: _BpmCard(bpm: _bpm, connected: _connected),
            ),
            const SizedBox(height: 14),

            _StateCard(state: _state, alert: alert, waiting: waiting),
            const SizedBox(height: 14),

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

            if (!_connected && !_connecting) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar conexión'),
                  onPressed: () {
                    _disposed = false;
                    _retries  = 0;
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
// ARDUINO PAGE — USB Serial + MPU6050
// ─────────────────────────────────────────────────────────────────────────────
// Protocolo esperado del Arduino (Serial.println):
//   CABECEO:1,COUNT:3,AX:0.52,AY:-0.31,AZ:9.78,GX:0.12,GY:0.05,GZ:-0.02
// ─────────────────────────────────────────────────────────────────────────────
class ArduinoPage extends StatefulWidget {
  const ArduinoPage({super.key});

  @override
  State<ArduinoPage> createState() => _ArduinoPageState();
}

class _ArduinoPageState extends State<ArduinoPage> {
  List<String> _ports      = [];
  SerialPort?  _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _sub;

  bool   _connected      = false;
  bool   _connecting     = false;
  String _connectedPort  = '';
  String _errorMsg       = '';
  String _buffer         = '';

  // MPU data
  bool   _cabeceo      = false;
  int    _cabeceoCount = 0;
  double _ax = 0, _ay = 0, _az = 0;
  double _gx = 0, _gy = 0, _gz = 0;
  String _rawSerial    = '--';

  @override
  void initState() {
    super.initState();
    _refreshPorts();
  }

  @override
  void dispose() {
    _doDisconnect();
    super.dispose();
  }

  void _refreshPorts() {
    setState(() {
      _ports    = SerialPort.availablePorts;
      _errorMsg = '';
    });
  }

  Future<void> _connect(String portName) async {
    if (_connecting) return;
    setState(() { _connecting = true; _errorMsg = ''; });

    try {
      final port = SerialPort(portName);
      if (!port.openReadWrite()) {
        final err = SerialPort.lastError;
        throw Exception(err?.message ?? 'No se pudo abrir $portName');
      }

      final config = SerialPortConfig()
        ..baudRate = kBaudRate
        ..bits     = 8
        ..stopBits = 1
        ..parity   = SerialPortParity.none;
      port.config = config;
      config.dispose();

      final reader = SerialPortReader(port);
      _sub = reader.stream.listen(
        _onSerialData,
        onError: (_) { if (mounted) _doDisconnect(); },
      );

      setState(() {
        _port          = port;
        _reader        = reader;
        _connectedPort = portName;
        _connected     = true;
        _connecting    = false;
      });
    } catch (e) {
      setState(() { _connecting = false; _errorMsg = e.toString(); });
    }
  }

  void _doDisconnect() {
    _sub?.cancel();
    _sub = null;
    try { _reader?.close(); } catch (_) {}
    _reader = null;
    try { _port?.close(); } catch (_) {}
    try { _port?.dispose(); } catch (_) {}
    _port = null;
    if (mounted) {
      setState(() { _connected = false; _connectedPort = ''; });
    }
  }

  void _onSerialData(Uint8List data) {
    _buffer += utf8.decode(data, allowMalformed: true);
    while (_buffer.contains('\n')) {
      final idx  = _buffer.indexOf('\n');
      final line = _buffer.substring(0, idx).trim();
      _buffer    = _buffer.substring(idx + 1);
      if (line.isNotEmpty) _parseLine(line);
    }
  }

  void _parseLine(String line) {
    bool   tempCabeceo = _cabeceo;
    int    tempCount   = _cabeceoCount;
    double tempAx = _ax, tempAy = _ay, tempAz = _az;
    double tempGx = _gx, tempGy = _gy, tempGz = _gz;

    for (final part in line.split(',')) {
      final kv = part.split(':');
      if (kv.length != 2) continue;
      final key = kv[0].trim().toUpperCase();
      final val = kv[1].trim();
      switch (key) {
        case 'CABECEO':
          tempCabeceo = val == '1' ||
              val.toUpperCase() == 'SI' ||
              val.toUpperCase() == 'DETECTADO';
          break;
        case 'COUNT': tempCount = int.tryParse(val)    ?? tempCount; break;
        case 'AX':    tempAx    = double.tryParse(val) ?? tempAx;    break;
        case 'AY':    tempAy    = double.tryParse(val) ?? tempAy;    break;
        case 'AZ':    tempAz    = double.tryParse(val) ?? tempAz;    break;
        case 'GX':    tempGx    = double.tryParse(val) ?? tempGx;    break;
        case 'GY':    tempGy    = double.tryParse(val) ?? tempGy;    break;
        case 'GZ':    tempGz    = double.tryParse(val) ?? tempGz;    break;
      }
    }

    if (mounted) {
      setState(() {
        _cabeceo      = tempCabeceo;
        _cabeceoCount = tempCount;
        _ax = tempAx; _ay = tempAy; _az = tempAz;
        _gx = tempGx; _gy = tempGy; _gz = tempGz;
        _rawSerial    = line;
      });
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Row(
          children: [
            Icon(Icons.usb, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Text(
              'Arduino Micro / MPU6050',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          if (_connected)
            IconButton(
              onPressed: _doDisconnect,
              icon: const Icon(Icons.usb_off, color: Colors.redAccent),
              tooltip: 'Desconectar',
            ),
          IconButton(
            onPressed: _refreshPorts,
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Actualizar puertos',
          ),
        ],
      ),
      body: _connected ? _buildDataView() : _buildPortSelector(),
    );
  }

  // ── Selector de puertos ───────────────────────────────────────────────────
  Widget _buildPortSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: const Color(0xFF161B22),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Puertos serie disponibles',
                style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                'Selecciona el puerto COM del Arduino Micro',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),

        if (_errorMsg.isNotEmpty)
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: Colors.redAccent.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.redAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_errorMsg,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13)),
                ),
              ],
            ),
          ),

        Expanded(
          child: _ports.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.usb_off,
                          size: 64, color: Colors.grey.shade700),
                      const SizedBox(height: 16),
                      Text(
                        'No se encontraron puertos serie',
                        style:
                            TextStyle(color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Conecta el Arduino Micro por USB\ny presiona Actualizar',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
                        ),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Actualizar puertos'),
                        onPressed: _refreshPorts,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _ports.length,
                  itemBuilder: (_, i) {
                    final portName = _ports[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: const Color(0xFF1C2128),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _connecting
                              ? null
                              : () => _connect(portName),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.orangeAccent
                                      .withOpacity(0.3)),
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: Colors.orange
                                        .withOpacity(0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.usb,
                                      color: Colors.orangeAccent,
                                      size: 24),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        portName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      Text(
                                        'Toca para conectar a $kBaudRate baud',
                                        style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                _connecting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.orangeAccent,
                                        ),
                                      )
                                    : const Icon(Icons.chevron_right,
                                        color: Colors.white30),
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
    );
  }

  // ── Vista de datos MPU ────────────────────────────────────────────────────
  Widget _buildDataView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Estado de conexión
          _ArduinoStatusCard(portName: _connectedPort),
          const SizedBox(height: 14),

          // Cabeceo + conteo
          _CabeceoCard(detected: _cabeceo, count: _cabeceoCount),
          const SizedBox(height: 14),

          // Acelerómetro
          _MpuSensorCard(
            title: 'Acelerómetro',
            icon: Icons.speed,
            color: Colors.blueAccent,
            labels: const ['AX', 'AY', 'AZ'],
            values: [_ax, _ay, _az],
            unit: 'g',
          ),
          const SizedBox(height: 14),

          // Giroscopio
          _MpuSensorCard(
            title: 'Giroscopio',
            icon: Icons.rotate_90_degrees_ccw,
            color: Colors.purpleAccent,
            labels: const ['GX', 'GY', 'GZ'],
            values: [_gx, _gy, _gz],
            unit: '°/s',
          ),
          const SizedBox(height: 14),

          // Raw serial
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
                  'Datos RAW (Serial)',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _rawSerial,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS — BLE
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
      iconColor   = Colors.tealAccent;
      icon        = Icons.check_circle;
    } else if (connecting) {
      borderColor = Colors.amber.withOpacity(0.4);
      iconColor   = Colors.amber;
      icon        = Icons.sync;
    } else {
      borderColor = Colors.redAccent.withOpacity(0.4);
      iconColor   = Colors.redAccent;
      icon        = Icons.error_outline;
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
                      strokeWidth: 2, color: iconColor),
                )
              : Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(status,
                style:
                    TextStyle(color: Colors.grey.shade300, fontSize: 14)),
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
          color: connected
              ? Colors.red.withOpacity(0.3)
              : Colors.white10,
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
      bg        = const Color(0xFF1C2128);
      border    = Colors.white12;
      textColor = Colors.grey;
      icon      = Icons.hourglass_empty;
    } else if (alert) {
      bg        = Colors.red.shade900.withOpacity(0.4);
      border    = Colors.redAccent.withOpacity(0.6);
      textColor = Colors.redAccent.shade100;
      icon      = Icons.warning_amber_rounded;
    } else {
      bg        = Colors.teal.shade900.withOpacity(0.3);
      border    = Colors.tealAccent.withOpacity(0.4);
      textColor = Colors.tealAccent.shade100;
      icon      = Icons.check_circle_outline;
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

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS — Arduino / MPU6050
// ─────────────────────────────────────────────────────────────────────────────

class _ArduinoStatusCard extends StatelessWidget {
  final String portName;
  const _ArduinoStatusCard({required this.portName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2128),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: Colors.orangeAccent.withOpacity(0.5), width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.usb, color: Colors.orangeAccent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Arduino Micro conectado',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  portName,
                  style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'MPU6050',
              style: TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _CabeceoCard extends StatelessWidget {
  final bool detected;
  final int count;

  const _CabeceoCard({required this.detected, required this.count});

  @override
  Widget build(BuildContext context) {
    final Color bg = detected
        ? Colors.red.shade900.withOpacity(0.5)
        : const Color(0xFF1C2128);
    final Color border =
        detected ? Colors.redAccent.withOpacity(0.7) : Colors.white12;
    final Color textColor =
        detected ? Colors.redAccent.shade100 : Colors.grey.shade400;
    final IconData icon =
        detected ? Icons.warning_amber_rounded : Icons.person;
    final String label =
        detected ? '¡CABECEO DETECTADO!' : 'Sin cabeceo';

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
          Icon(icon, color: textColor, size: 52),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: textColor,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.repeat, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 6),
                Text(
                  'Total cabeceos: $count',
                  style: TextStyle(
                      color: Colors.grey.shade300, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MpuSensorCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> labels;
  final List<double> values;
  final String unit;

  const _MpuSensorCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.labels,
    required this.values,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2128),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(3, (i) {
              return Expanded(
                child: Column(
                  children: [
                    Text(
                      labels[i],
                      style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      values[i].toStringAsFixed(2),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      unit,
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 10),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
