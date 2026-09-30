import "dart:async";
import "dart:io";
import "dart:typed_data";

import "package:archive/archive_io.dart";
import "package:test/test.dart";
import "package:urwalking_sensors_network/urwalking_sensors_network.dart";

/// A receiver that accepts one upload, unpacks it and sends `reply`.
class FakeUploadReceiver {
  FakeUploadReceiver._(this._server, String reply) {
    _subscription = _server.listen((Socket socket) async {
      BytesBuilder received = BytesBuilder();
      await for (Uint8List chunk in socket) {
        received.add(chunk);
        Uint8List bytes = received.toBytes();
        if (bytes.length < 8) {
          continue;
        }
        int length = ByteData.sublistView(bytes, 0, 8).getUint64(0);
        if (bytes.length - 8 >= length) {
          archive.complete(TarDecoder().decodeBytes(bytes.sublist(8)));
          socket.write(reply);
          await socket.close();
          break;
        }
      }
    });
  }

  static Future<FakeUploadReceiver> start({String reply = "OK"}) async =>
      FakeUploadReceiver._(
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
        reply,
      );

  final ServerSocket _server;
  late final StreamSubscription<Socket> _subscription;
  final Completer<Archive> archive = Completer<Archive>();

  int get port => _server.port;

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close();
  }
}

void main() {
  late Directory recording;

  setUp(() async {
    recording = await Directory.systemTemp.createTemp("upload_test");
    await File(
      "${recording.path}/accelerometer_raw.csv",
    ).writeAsString("phone_ts_ms,acc_x\n1000,0.5\n");
    await Directory("${recording.path}/images").create();
    await File(
      "${recording.path}/images/frame_1.jpg",
    ).writeAsBytes(<int>[1, 2, 3]);
  });

  tearDown(() => recording.delete(recursive: true));

  test("uploads every file with paths relative to the directory", () async {
    FakeUploadReceiver receiver = await FakeUploadReceiver.start();
    List<String> statuses = <String>[];

    await uploadDirectory(
      recording,
      host: "127.0.0.1",
      port: receiver.port,
      onStatus: statuses.add,
    );
    Archive archive = await receiver.archive.future;
    await receiver.close();

    expect(
      archive.files.map((ArchiveFile file) => file.name),
      unorderedEquals(<String>["accelerometer_raw.csv", "images/frame_1.jpg"]),
    );
    ArchiveFile csv = archive.findFile("accelerometer_raw.csv")!;
    expect(String.fromCharCodes(csv.content as List<int>), contains("1000"));
    expect(statuses.first, "Packing data…");
  });

  test("leaves out files rejected by include", () async {
    FakeUploadReceiver receiver = await FakeUploadReceiver.start();

    await uploadDirectory(
      recording,
      host: "127.0.0.1",
      port: receiver.port,
      include: (String path) => !path.startsWith("images/"),
    );
    Archive archive = await receiver.archive.future;
    await receiver.close();

    expect(archive.files.map((ArchiveFile file) => file.name), <String>[
      "accelerometer_raw.csv",
    ]);
  });

  test("reports errors sent by the receiver", () async {
    FakeUploadReceiver receiver = await FakeUploadReceiver.start(
      reply: "ERROR: disk full",
    );

    await expectLater(
      uploadDirectory(recording, host: "127.0.0.1", port: receiver.port),
      throwsA(
        isA<UploadException>().having(
          (UploadException e) => e.message,
          "message",
          contains("disk full"),
        ),
      ),
    );
    await receiver.close();
  });

  test("refuses to upload an empty recording", () async {
    Directory empty = await Directory.systemTemp.createTemp("upload_empty");
    await expectLater(
      uploadDirectory(empty, host: "127.0.0.1", port: 1),
      throwsA(isA<UploadException>()),
    );
    await empty.delete();
  });
}
