import "dart:async";
import "dart:convert";
import "dart:io";

import "package:urwalking_sensors/urwalking_sensors.dart";

/// The state of a network connection.
enum ConnectionStatus {
  /// Not connected and not trying to connect.
  disconnected,

  /// A connection attempt is in progress.
  connecting,

  /// Connected; data is being sent.
  connected,

  /// The last connection attempt failed or the connection was lost; a
  /// reconnect is scheduled.
  error,
}

/// Streams samples live to a receiver over TCP, as described in
/// `docs/protocol.md` (one JSON object per line).
///
/// Besides the samples, it sends a `clock` message every [clockInterval] so
/// the receiver can measure the offset between the phone's clock and its
/// own.
///
/// The sink connects in the background and reconnects with exponential
/// backoff if the connection is lost. Samples recorded while disconnected
/// are dropped (see [droppedSamples]), so combine it with a CsvSink when no
/// data may be lost.
class TcpStreamSink extends SampleSink {
  /// Creates a sink that streams to [host]:[port].
  ///
  /// Clock messages are timestamped with [clock], which defaults to
  /// [SensorClock.shared], the clock of the built-in sensors.
  TcpStreamSink({
    required this.host,
    this.port = 5001,
    SensorClock? clock,
    this.clockInterval = const Duration(milliseconds: 33),
    this.connectTimeout = const Duration(seconds: 5),
    this.maxReconnectDelay = const Duration(seconds: 16),
    this.onStatusChange,
  }) : clock = clock ?? SensorClock.shared;

  /// The receiver's host name or IP address. Use `127.0.0.1` with
  /// `adb reverse` over USB.
  final String host;

  /// The receiver's port.
  final int port;

  /// The clock for `clock` messages.
  final SensorClock clock;

  /// How often a `clock` message is sent.
  final Duration clockInterval;

  /// How long a single connection attempt may take.
  final Duration connectTimeout;

  /// The longest wait between reconnect attempts.
  final Duration maxReconnectDelay;

  /// Called whenever [status] changes.
  final void Function(ConnectionStatus status)? onStatusChange;

  static const Duration _initialReconnectDelay = Duration(seconds: 1);

  Socket? _socket;
  Timer? _clockTimer;
  Timer? _reconnectTimer;
  bool _isOpen = false;
  Duration _reconnectDelay = _initialReconnectDelay;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  int _droppedSamples = 0;

  /// The current connection state.
  ConnectionStatus get status => _status;

  /// How many samples were dropped because the sink was not connected.
  int get droppedSamples => _droppedSamples;

  /// Starts connecting. Returns after the first connection attempt, whether
  /// it succeeded or not; failed attempts are retried in the background.
  @override
  Future<void> open() async {
    _isOpen = true;
    _droppedSamples = 0;
    _reconnectDelay = _initialReconnectDelay;
    await _connect();
  }

  @override
  void add(SensorSample sample) {
    if (_socket == null) {
      _droppedSamples++;
      return;
    }
    _send(<String, Object?>{
      "type": "sample",
      "sensor": sample.sensorId,
      "ts_ms": sample.timestamp.millisecondsSinceEpoch,
      "values": <String, Object?>{
        for (MapEntry<String, Object?> entry in sample.values.entries)
          entry.key: _jsonSafe(entry.value),
      },
    });
  }

  /// Flushes pending data and closes the connection.
  @override
  Future<void> close() async {
    _isOpen = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _clockTimer?.cancel();
    _clockTimer = null;
    Socket? socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.flush();
        await socket.close();
      } on SocketException {
        // The receiver is already gone; nothing left to flush.
      }
    }
    _setStatus(ConnectionStatus.disconnected);
  }

  Future<void> _connect() async {
    _setStatus(ConnectionStatus.connecting);
    Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: connectTimeout);
    } on SocketException {
      _scheduleReconnect();
      return;
    }
    if (!_isOpen) {
      await socket.close();
      return;
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    _socket = socket;
    _reconnectDelay = _initialReconnectDelay;
    _setStatus(ConnectionStatus.connected);
    _send(<String, Object?>{"type": "hello", "protocol": 1});
    _sendClock();
    _clockTimer = Timer.periodic(clockInterval, (_) => _sendClock());
    unawaited(
      socket.done.then(
        (_) => _onConnectionLost(socket),
        onError: (Object _) => _onConnectionLost(socket),
      ),
    );
  }

  void _sendClock() => _send(<String, Object?>{
    "type": "clock",
    "ts_ms": clock.now().millisecondsSinceEpoch,
  });

  void _send(Map<String, Object?> message) =>
      _socket?.write("${jsonEncode(message)}\n");

  void _onConnectionLost(Socket socket) {
    if (_socket != socket) {
      return;
    }
    _socket = null;
    _clockTimer?.cancel();
    _clockTimer = null;
    if (_isOpen) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _setStatus(ConnectionStatus.error);
    if (!_isOpen) {
      return;
    }
    _reconnectTimer = Timer(_reconnectDelay, () => unawaited(_connect()));
    Duration doubled = _reconnectDelay * 2;
    _reconnectDelay = doubled > maxReconnectDelay ? maxReconnectDelay : doubled;
  }

  void _setStatus(ConnectionStatus status) {
    if (status == _status) {
      return;
    }
    _status = status;
    onStatusChange?.call(status);
  }

  /// JSON has no NaN or infinity.
  static Object? _jsonSafe(Object? value) =>
      value is double && !value.isFinite ? null : value;
}
