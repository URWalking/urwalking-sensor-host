import "dart:async";
import "dart:convert";
import "dart:io";

import "package:test/test.dart";
import "package:urwalking_sensors/urwalking_sensors.dart";
import "package:urwalking_sensors_network/urwalking_sensors_network.dart";

/// A receiver that collects the JSON lines of every connection.
class FakeReceiver {
  FakeReceiver._(this._server) {
    _subscription = _server.listen((Socket socket) {
      connections++;
      _lineSubscriptions.add(
        utf8.decoder
            .bind(socket)
            .transform(const LineSplitter())
            .listen(
              (String line) =>
                  messages.add(jsonDecode(line) as Map<String, Object?>),
            ),
      );
    });
  }

  static Future<FakeReceiver> start() async =>
      FakeReceiver._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  final ServerSocket _server;
  late final StreamSubscription<Socket> _subscription;
  final List<StreamSubscription<String>> _lineSubscriptions =
      <StreamSubscription<String>>[];
  final List<Map<String, Object?>> messages = <Map<String, Object?>>[];
  int connections = 0;

  int get port => _server.port;

  List<Map<String, Object?>> ofType(String type) => <Map<String, Object?>>[
    for (Map<String, Object?> message in messages)
      if (message["type"] == type) message,
  ];

  Future<void> close() async {
    for (StreamSubscription<String> subscription in _lineSubscriptions) {
      await subscription.cancel();
    }
    await _subscription.cancel();
    await _server.close();
  }
}

/// Waits until [condition] holds, or fails after a few seconds.
Future<void> eventually(bool Function() condition) async {
  for (int i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

void main() {
  late FakeReceiver receiver;

  setUp(() async => receiver = await FakeReceiver.start());
  tearDown(() => receiver.close());

  test("sends hello, clock messages and samples as JSON lines", () async {
    List<ConnectionStatus> statuses = <ConnectionStatus>[];
    TcpStreamSink sink = TcpStreamSink(
      host: "127.0.0.1",
      port: receiver.port,
      clockInterval: const Duration(milliseconds: 10),
      onStatusChange: statuses.add,
    );

    await sink.open();
    expect(sink.status, ConnectionStatus.connected);
    sink.add(
      SensorSample(
        sensorId: "accelerometer",
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
        values: const <String, Object?>{
          "acc_x": 0.5,
          "acc_y": double.nan,
          "label": "a,b",
        },
      ),
    );
    await eventually(() => receiver.ofType("clock").length >= 3);
    await sink.close();
    await eventually(() => receiver.ofType("sample").isNotEmpty);

    expect(receiver.messages.first, <String, Object?>{
      "type": "hello",
      "protocol": 1,
    });
    expect(receiver.ofType("sample").single, <String, Object?>{
      "type": "sample",
      "sensor": "accelerometer",
      "ts_ms": 1000,
      "values": <String, Object?>{"acc_x": 0.5, "acc_y": null, "label": "a,b"},
    });
    expect(receiver.ofType("clock").first["ts_ms"], isA<int>());
    expect(statuses, <ConnectionStatus>[
      ConnectionStatus.connecting,
      ConnectionStatus.connected,
      ConnectionStatus.disconnected,
    ]);
    expect(sink.droppedSamples, 0);
  });

  test("drops samples and retries while the receiver is down", () async {
    int port = receiver.port;
    await receiver.close();
    TcpStreamSink sink = TcpStreamSink(host: "127.0.0.1", port: port);

    await sink.open();
    sink.add(
      SensorSample(
        sensorId: "gyroscope",
        timestamp: DateTime.now(),
        values: const <String, Object?>{"gyro_x": 1.0},
      ),
    );
    ConnectionStatus statusWhileDown = sink.status;
    await sink.close();

    expect(statusWhileDown, ConnectionStatus.error);
    expect(sink.droppedSamples, 1);
    expect(sink.status, ConnectionStatus.disconnected);
  });

  test("reconnects after the receiver closes the connection", () async {
    List<Socket> accepted = <Socket>[];
    ServerSocket server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    StreamSubscription<Socket> subscription = server.listen(accepted.add);
    TcpStreamSink reconnecting = TcpStreamSink(
      host: "127.0.0.1",
      port: server.port,
    );

    await reconnecting.open();
    await eventually(() => accepted.length == 1);
    accepted.first.destroy();
    // The first reconnect attempt happens after one second.
    await eventually(() => accepted.length == 2);
    expect(reconnecting.status, ConnectionStatus.connected);

    await reconnecting.close();
    for (Socket socket in accepted) {
      socket.destroy();
    }
    await subscription.cancel();
    await server.close();
  });
}
