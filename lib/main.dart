// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const String kServiceUUID = "12345678-1234-1234-1234-123456789abc";
const String kCharacteristicUUID = "12345678-1234-1234-1234-123456789abd";
const String kDeviceName = "BiometricSensor";

void main() => runApp(const SafeSleepApp());

class SafeSleepApp extends StatelessWidget {
  const SafeSleepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Safe Sleep Hours',
      theme: ThemeData(
        colorSchemeSeed: Colors.cyan,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const ScanPage(),
    );
  }
}

// ─── SCAN PAGE ────────────────────────────────────────────────────────────────
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage>
    with SingleTickerProviderStateMixin {
  ScanResult? _esp32;
  StreamSubscription? _scanSub;
  StreamSubscription? _isScanSub;
  bool _scanning = false;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _startScan();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _scanSub?.cancel();
    _isScanSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() => _esp32 = null);
    await _scanSub?.cancel();
    await _isScanSub?.cancel();

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.device.platformName == kDeviceName) {
          if (!mounted) return;
          setState(() => _esp32 = r);
          FlutterBluePlus.stopScan();
          return;
        }
      }
    });

    _isScanSub = FlutterBluePlus.isScanning.listen((v) {
      if (mounted) setState(() => _scanning = v);
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );
    } catch (e) {
      debugPrint('Scan error: $e');
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => DataPage(device: device)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final found = _esp32 != null;

    return Scaffold(
      backgroundColor: const Color(0xFF050A0E),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.cyan.withOpacity(0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.cyan.withOpacity(0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.remove_red_eye_outlined,
                      color: Colors.cyanAccent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Safe Sleep Hours',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'Panel de monitoreo · ESP32',
                        style: TextStyle(
                          color: Colors.cyan,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Main
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (_, child) => Transform.scale(
                          scale: _scanning && !found ? _pulseAnim.value : 1.0,
                          child: child,
                        ),
                        child: Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: found
                                ? Colors.cyan.withOpacity(0.12)
                                : Colors.cyan.withOpacity(0.05),
                            border: Border.all(
                              color: found
                                  ? Colors.cyanAccent
                                  : Colors.cyan.withOpacity(0.3),
                              width: found ? 2 : 1.5,
                            ),
                          ),
                          child: Icon(
                            found
                                ? Icons.bluetooth_connected
                                : Icons.bluetooth_searching,
                            color: found
                                ? Colors.cyanAccent
                                : Colors.cyan.shade600,
                            size: 50,
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      Text(
                        found
                            ? 'Lentes encontradas'
                            : _scanning
                                ? 'Buscando dispositivo...'
                                : 'Dispositivo no encontrado',
                        style: TextStyle(
                          color: found ? Colors.cyanAccent : Colors.grey,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      if (_scanning && !found) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: 120,
                          child: LinearProgressIndicator(
                            color: Colors.cyan,
                            backgroundColor: Colors.cyan.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],

                      const SizedBox(height: 30),

                      if (found)
                        _DeviceCard(
                          result: _esp32!,
                          onConnect: () => _connect(_esp32!.device),
                        )
                      else if (!_scanning)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.cyan.shade700,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 36,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Buscar de nuevo'),
                          onPressed: _startScan,
                        ),
                    ],
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Text(
                'Compatible solo con ESP32 "$kDeviceName"',
                style: TextStyle(color: Colors.grey.shade800, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final ScanResult result;
  final VoidCallback onConnect;

  const _DeviceCard({required this.result, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final rssi = result.rssi;
    final Color signalColor;
    final String signalLabel;
    if (rssi >= -60) {
      signalColor = Colors.cyanAccent;
      signalLabel = 'Excelente';
    } else if (rssi >= -75) {
      signalColor = Colors.yellowAccent;
      signalLabel = 'Buena';
    } else if (rssi >= -85) {
      signalColor = Colors.orangeAccent;
      signalLabel = 'Regular';
    } else {
      signalColor = Colors.redAccent;
      signalLabel = 'Débil';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1520),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.cyanAccent.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.cyan.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.remove_red_eye_outlined,
                  color: Colors.cyanAccent,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          result.device.platformName,
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.cyan.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            'ESP32',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.cyanAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      result.device.remoteId.toString(),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Icon(Icons.wifi, color: signalColor, size: 18),
                  Text(
                    signalLabel,
                    style: TextStyle(color: signalColor, fontSize: 9),
                  ),
                  Text(
                    '$rssi dBm',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.cyan.shade700,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onConnect,
              child: const Text(
                'Iniciar monitoreo',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── DATA PAGE ────────────────────────────────────────────────────────────────
// Estados FSM: MONITOREO → PENDIENTE → ALERTA
// Protocolo BLE esperado del ESP32 (CSV):
//   BPM:72,STATE:MONITOREO,CABECEO:0,COUNT:3,AX:0.12,AY:-0.05,AZ:9.81,GX:0.01,GY:0.02,GZ:-0.01
class DataPage extends StatefulWidget {
  final BluetoothDevice device;
  const DataPage({super.key, required this.device});

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> with TickerProviderStateMixin {
  bool _connected = false;
  bool _connecting = false;
  bool _disposed = false;
  String _status = 'Conectando...';

  // Fisiológico
  int _bpm = 0;
  int _prevBpm = 0;

  // FSM
  String _state = 'MONITOREO';

  // Cinemático
  bool _cabeceo = false;
  int _cabeceoCount = 0;
  double _ax = 0, _ay = 0, _az = 0;
  double _gx = 0, _gy = 0, _gz = 0;

  StreamSubscription? _notifySub;
  StreamSubscription? _connectionSub;

  static const int _maxRetries = 3;
  int _retries = 0;

  late AnimationController _heartCtrl;
  late Animation<double> _heartAnim;

  @override
  void initState() {
    super.initState();
    _heartCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _heartAnim = Tween(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _heartCtrl, curve: Curves.easeOut),
    );
    _connectToDevice();
  }

  @override
  void dispose() {
    _disposed = true;
    _heartCtrl.dispose();
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

      await targetChar.setNotifyValue(true);
      _notifySub = targetChar.onValueReceived.listen(_onDataReceived);

      _retries = 0;
      _setStatus('Monitoreando', connecting: false, connected: true);
    } on FlutterBluePlusException catch (e) {
      debugPrint('BLE error: $e');
      _handleConnectionError(e.toString());
    } catch (e) {
      debugPrint('Error: $e');
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
    _setStatus('Error de conexión', connecting: false, connected: false);
    _autoReconnect();
  }

  void _autoReconnect() {
    if (_disposed || _retries >= _maxRetries) {
      if (!_disposed && _retries >= _maxRetries) {
        _setStatus(
          'Sin conexión tras $_maxRetries intentos',
          connecting: false,
          connected: false,
        );
      }
      return;
    }
    _retries++;
    _setStatus(
      'Reconectando ($_retries/$_maxRetries)...',
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

  void _onDataReceived(List<int> value) {
    final text = utf8.decode(value, allowMalformed: true);
    _parseData(text);
  }

  void _parseData(String raw) {
    int tempBpm = _bpm;
    String tempState = _state;
    bool tempCabeceo = _cabeceo;
    int tempCount = _cabeceoCount;
    double tempAx = _ax, tempAy = _ay, tempAz = _az;
    double tempGx = _gx, tempGy = _gy, tempGz = _gz;

    for (final part in raw.split(',')) {
      final kv = part.split(':');
      if (kv.length != 2) continue;
      final key = kv[0].trim().toUpperCase();
      final val = kv[1].trim();
      switch (key) {
        case 'BPM':
          tempBpm = int.tryParse(val) ?? tempBpm;
          break;
        case 'STATE':
          tempState = val.toUpperCase();
          break;
        case 'CABECEO':
          tempCabeceo =
              val == '1' ||
              val.toUpperCase() == 'SI' ||
              val.toUpperCase() == 'DETECTADO';
          break;
        case 'COUNT':
          tempCount = int.tryParse(val) ?? tempCount;
          break;
        case 'AX':
          tempAx = double.tryParse(val) ?? tempAx;
          break;
        case 'AY':
          tempAy = double.tryParse(val) ?? tempAy;
          break;
        case 'AZ':
          tempAz = double.tryParse(val) ?? tempAz;
          break;
        case 'GX':
          tempGx = double.tryParse(val) ?? tempGx;
          break;
        case 'GY':
          tempGy = double.tryParse(val) ?? tempGy;
          break;
        case 'GZ':
          tempGz = double.tryParse(val) ?? tempGz;
          break;
      }
    }

    if (!_disposed && mounted) {
      setState(() {
        _bpm = tempBpm;
        _state = tempState;
        _cabeceo = tempCabeceo;
        _cabeceoCount = tempCount;
        _ax = tempAx;
        _ay = tempAy;
        _az = tempAz;
        _gx = tempGx;
        _gy = tempGy;
        _gz = tempGz;
      });
      if (tempBpm != _prevBpm && tempBpm > 0) {
        _prevBpm = tempBpm;
        _heartCtrl.forward(from: 0);
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
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ScanPage()),
      );
    }
  }

  // ── Estado FSM helpers ────────────────────────────────────────────────────
  bool get _isAlerta => _state == 'ALERTA';
  bool get _isPendiente => _state == 'PENDIENTE';
  bool get _isMonitoreo =>
      _state == 'MONITOREO' || (!_isAlerta && !_isPendiente);

  Color get _stateColor {
    if (_isAlerta) return Colors.redAccent;
    if (_isPendiente) return Colors.amberAccent;
    return Colors.cyanAccent;
  }

  Color get _bpmColor {
    if (!_connected || _bpm == 0) return Colors.grey.shade700;
    if (_bpm < 60) return Colors.amberAccent; // Bradicardia → PENDIENTE
    if (_bpm < 100) return Colors.cyanAccent;
    if (_bpm < 140) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  String get _bpmZone {
    if (_bpm == 0) return '—';
    if (_bpm < 60) return 'BRADICARDIA';
    if (_bpm < 100) return 'NORMAL';
    if (_bpm < 140) return 'ELEVADO';
    return 'CRÍTICO';
  }

  @override
  Widget build(BuildContext context) {
    final ringSize = MediaQuery.of(context).size.width * 0.72;

    return Scaffold(
      backgroundColor: const Color(0xFF050A0E),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _disconnect,
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white38,
                      size: 16,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Safe Sleep Hours',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.3,
                          ),
                        ),
                        Text(
                          widget.device.remoteId.toString(),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 9,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_connecting)
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.amber,
                          ),
                        )
                      else
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _connected
                                ? Colors.cyanAccent
                                : Colors.redAccent,
                          ),
                        ),
                      const SizedBox(width: 5),
                      Text(
                        _connected
                            ? 'Activo'
                            : _connecting
                                ? 'Conectando'
                                : 'Sin señal',
                        style: TextStyle(
                          color: _connected
                              ? Colors.cyanAccent
                              : _connecting
                                  ? Colors.amber
                                  : Colors.redAccent,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _disconnect,
                    icon: const Icon(
                      Icons.power_settings_new,
                      color: Colors.redAccent,
                      size: 19,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Detener monitoreo',
                  ),
                ],
              ),
            ),

            // ── Content ───────────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    // BPM ring
                    SizedBox(
                      width: ringSize,
                      height: ringSize,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomPaint(
                            size: Size(ringSize, ringSize),
                            painter: _BpmRingPainter(
                              bpm: _bpm,
                              connected: _connected,
                              bpmColor: _bpmColor,
                              stateColor: _stateColor,
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedBuilder(
                                animation: _heartAnim,
                                builder: (_, child) => Transform.scale(
                                  scale: _connected && _bpm > 0
                                      ? _heartAnim.value
                                      : 1.0,
                                  child: child,
                                ),
                                child: Icon(
                                  Icons.favorite,
                                  color: _connected && _bpm > 0
                                      ? _bpmColor
                                      : Colors.grey.shade800,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _bpm > 0 ? '$_bpm' : '--',
                                style: TextStyle(
                                  fontSize: ringSize * 0.27,
                                  fontWeight: FontWeight.w900,
                                  color: _connected
                                      ? Colors.white
                                      : Colors.grey.shade800,
                                  height: 1,
                                ),
                              ),
                              Text(
                                'BPM',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                  letterSpacing: 4,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                              if (_bpm > 0) ...[
                                const SizedBox(height: 7),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _bpmColor.withOpacity(0.13),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _bpmZone,
                                    style: TextStyle(
                                      color: _bpmColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Estado FSM
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _FsmStateCard(
                        state: _state,
                        isAlerta: _isAlerta,
                        isPendiente: _isPendiente,
                        isMonitoreo: _isMonitoreo,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Cabeceo row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _CabeceoCard(
                        detected: _cabeceo,
                        count: _cabeceoCount,
                        connected: _connected,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // IMU datos
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _ImuCard(
                        ax: _ax,
                        ay: _ay,
                        az: _az,
                        gx: _gx,
                        gy: _gy,
                        gz: _gz,
                        connected: _connected,
                      ),
                    ),

                    // Reconectar
                    if (!_connected && !_connecting) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.cyan.shade700,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reconectar'),
                          onPressed: () {
                            _disposed = false;
                            _retries = 0;
                            _connectToDevice();
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
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

// ─── BPM Ring Painter ─────────────────────────────────────────────────────────
class _BpmRingPainter extends CustomPainter {
  final int bpm;
  final bool connected;
  final Color bpmColor;
  final Color stateColor;

  const _BpmRingPainter({
    required this.bpm,
    required this.connected,
    required this.bpmColor,
    required this.stateColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 22;
    const stroke = 13.0;

    // Outer subtle ring
    canvas.drawCircle(
      center,
      radius + 18,
      Paint()
        ..color = Colors.white.withOpacity(0.03)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withOpacity(0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    if (!connected) return;

    // 60 BPM threshold marker (bradicardia)
    const thresholdAngle = -math.pi / 2 + (60 / 200) * 2 * math.pi;
    final markerX = center.dx + radius * math.cos(thresholdAngle);
    final markerY = center.dy + radius * math.sin(thresholdAngle);
    canvas.drawCircle(
      Offset(markerX, markerY),
      4,
      Paint()..color = Colors.amberAccent.withOpacity(0.7),
    );

    if (bpm == 0) return;

    final progress = (bpm / 200).clamp(0.0, 1.0);
    final sweep = progress * 2 * math.pi;
    const startAngle = -math.pi / 2;

    // Glow
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweep,
      false,
      Paint()
        ..color = bpmColor.withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 10
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Progress arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweep,
      false,
      Paint()
        ..color = bpmColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    // End dot
    final endAngle = startAngle + sweep;
    canvas.drawCircle(
      Offset(
        center.dx + radius * math.cos(endAngle),
        center.dy + radius * math.sin(endAngle),
      ),
      stroke / 2 + 1,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_BpmRingPainter old) =>
      old.bpm != bpm ||
      old.connected != connected ||
      old.bpmColor != bpmColor ||
      old.stateColor != stateColor;
}

// ─── FSM State Card ───────────────────────────────────────────────────────────
class _FsmStateCard extends StatelessWidget {
  final String state;
  final bool isAlerta, isPendiente, isMonitoreo;

  const _FsmStateCard({
    required this.state,
    required this.isAlerta,
    required this.isPendiente,
    required this.isMonitoreo,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg, border, textColor;
    final IconData icon;
    final String label;

    if (isAlerta) {
      bg = Colors.red.shade900.withOpacity(0.3);
      border = Colors.redAccent.withOpacity(0.6);
      textColor = Colors.red.shade200;
      icon = Icons.warning_amber_rounded;
      label = 'ALERTA';
    } else if (isPendiente) {
      bg = Colors.amber.shade900.withOpacity(0.25);
      border = Colors.amberAccent.withOpacity(0.5);
      textColor = Colors.amberAccent;
      icon = Icons.access_time_filled;
      label = 'PENDIENTE';
    } else {
      bg = Colors.cyan.shade900.withOpacity(0.2);
      border = Colors.cyanAccent.withOpacity(0.35);
      textColor = Colors.cyanAccent;
      icon = Icons.check_circle_outline;
      label = 'MONITOREO';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 26),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Estado FSM',
                style: TextStyle(
                  color: textColor.withOpacity(0.5),
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          if (isAlerta) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.redAccent.withOpacity(0.5),
                ),
              ),
              child: const Text(
                'MOTOR\nHÁPTICO',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ] else if (isPendiente) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.amberAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.amberAccent.withOpacity(0.4),
                ),
              ),
              child: const Text(
                'BRADICARDIA\nDETECTADA',
                style: TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Cabeceo Card ─────────────────────────────────────────────────────────────
class _CabeceoCard extends StatelessWidget {
  final bool detected;
  final int count;
  final bool connected;

  const _CabeceoCard({
    required this.detected,
    required this.count,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = detected
        ? Colors.red.shade900.withOpacity(0.3)
        : const Color(0xFF0A1520);
    final Color border = detected
        ? Colors.redAccent.withOpacity(0.55)
        : Colors.white.withOpacity(0.07);
    final Color textColor = detected ? Colors.red.shade200 : Colors.grey;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(
            detected ? Icons.airline_seat_recline_extra : Icons.person_outline,
            color: textColor,
            size: 26,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cabeceo (IMU)',
                  style: TextStyle(
                    color: textColor.withOpacity(0.5),
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  detected ? '¡CABECEO DETECTADO!' : 'Sin cabeceo',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
                Text(
                  'total',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── IMU Card ─────────────────────────────────────────────────────────────────
class _ImuCard extends StatelessWidget {
  final double ax, ay, az, gx, gy, gz;
  final bool connected;

  const _ImuCard({
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1520),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sensors,
                color: Colors.cyan.shade600,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                'MPU-6050 · Telemetría cinemática',
                style: TextStyle(
                  color: Colors.cyan.shade600,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ImuSection(
                  label: 'ACELERÓMETRO',
                  color: Colors.blueAccent,
                  names: const ['AX', 'AY', 'AZ'],
                  values: [ax, ay, az],
                  unit: 'g',
                  connected: connected,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ImuSection(
                  label: 'GIROSCOPIO',
                  color: Colors.purpleAccent,
                  names: const ['GX', 'GY', 'GZ'],
                  values: [gx, gy, gz],
                  unit: '°/s',
                  connected: connected,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImuSection extends StatelessWidget {
  final String label;
  final Color color;
  final List<String> names;
  final List<double> values;
  final String unit;
  final bool connected;

  const _ImuSection({
    required this.label,
    required this.color,
    required this.names,
    required this.values,
    required this.unit,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color.withOpacity(0.7),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(3, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  names[i],
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  connected ? values[i].toStringAsFixed(2) : '--',
                  style: TextStyle(
                    color: connected ? Colors.white70 : Colors.grey.shade700,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  unit,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 9),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
