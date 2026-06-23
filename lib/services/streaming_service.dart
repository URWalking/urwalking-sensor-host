import "dart:async";
import "dart:io";

import "package:urwalking_sensor_host/services/storage_utils.dart";

// ignore_for_file: public_member_api_docs // internal app service, no public API

enum StreamingStatus { disconnected, connecting, connected, error }

class StreamingService {
  static const String _host = "127.0.0.1";
  static const int _port = 5001;
  static const int _intervalMs = 33; // ~30 Hz
  static const int _maxReconnectDelayMs = 16000;

  Socket? _socket;
  Timer? _sendTimer;
  Timer? _reconnectTimer;
  bool _shouldStop = false;
  int _reconnectDelayMs = 1000;
  StreamingStatus _status = StreamingStatus.disconnected;

  IOSink? _logSink;

  Function(StreamingStatus)? onStatusChange;

  StreamingStatus get status => _status;

  Future<void> start() async {
    _shouldStop = false;
    _reconnectDelayMs = 1000;
    await _openLogFile();
    await _connect();
  }

  Future<void> stop() async {
    _shouldStop = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sendTimer?.cancel();
    _sendTimer = null;
    await _socket?.close();
    _socket = null;
    await _logSink?.flush();
    await _logSink?.close();
    _logSink = null;
    _setStatus(StreamingStatus.disconnected);
  }

  Future<void> dispose() => stop();

  Future<void> _openLogFile() async {
    Directory logsDir = await getLogsDirectory();
    File logFile = File(
      "${logsDir.path}${Platform.pathSeparator}streaming_timestamps.csv",
    );
    _logSink = logFile.openWrite(mode: FileMode.append);
    _logSink!.writeln("phone_ts_ms");
  }

  Future<void> _connect() async {
    _setStatus(StreamingStatus.connecting);
    try {
      Socket socket = await Socket.connect(
        _host,
        _port,
        timeout: const Duration(seconds: 5),
      );
      if (_shouldStop) {
        await socket.close();
        return;
      }
      _socket = socket;
      _reconnectDelayMs = 1000;
      _setStatus(StreamingStatus.connected);
      _sendTimer = Timer.periodic(
        const Duration(milliseconds: _intervalMs),
        (_) => _sendTimestamp(),
      );
      unawaited(
        socket.done
            .then((_) => _onDisconnected())
            .catchError((_) => _onDisconnected()),
      );
    } on Exception catch (_) {
      _scheduleReconnect();
    }
  }

  void _sendTimestamp() {
    if (_status != StreamingStatus.connected || _socket == null) {
      return;
    }
    try {
      String ts = DateTime.now().millisecondsSinceEpoch.toString();
      _socket!.add("$ts\n".codeUnits);
      _logSink?.writeln(ts);
    } on Exception catch (_) {
      _onDisconnected();
    }
  }

  void _onDisconnected() {
    _sendTimer?.cancel();
    _sendTimer = null;
    _socket = null;
    _setStatus(StreamingStatus.disconnected);
    if (!_shouldStop) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _setStatus(StreamingStatus.error);
    _reconnectTimer = Timer(
      Duration(milliseconds: _reconnectDelayMs),
      _connect,
    );
    _reconnectDelayMs =
        (_reconnectDelayMs * 2).clamp(0, _maxReconnectDelayMs);
  }

  void _setStatus(StreamingStatus s) {
    _status = s;
    onStatusChange?.call(s);
  }
}
