import "dart:async";
import "dart:io";
import "dart:isolate";
import "dart:typed_data";

import "package:archive/archive_io.dart";

/// The receiver rejected an upload, or there was nothing to upload.
class UploadException implements Exception {
  /// Creates an exception with a [message] for the user.
  const UploadException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}

/// Uploads the recording in [directory] to a receiver, as described in
/// `docs/protocol.md`: the directory is packed into a tar archive and sent
/// to [host]:[port], and the receiver confirms with `OK`.
///
/// Files are included when [include] returns true for their path relative
/// to [directory] (with `/` as separator, e.g. `images/frame_1.jpg`); by
/// default everything is included. [onStatus] receives progress messages
/// for the user.
///
/// Throws an [UploadException] if there is nothing to upload or the
/// receiver reports an error, a [SocketException] if the receiver cannot be
/// reached, and a [TimeoutException] if it does not answer within
/// [responseTimeout].
Future<void> uploadDirectory(
  Directory directory, {
  required String host,
  int port = 5000,
  bool Function(String relativePath)? include,
  void Function(String message)? onStatus,
  Duration connectTimeout = const Duration(seconds: 10),
  Duration responseTimeout = const Duration(minutes: 2),
}) async {
  onStatus?.call("Packing data…");
  List<(String, String)> files = await _listFiles(directory, include);
  if (files.isEmpty) {
    throw const UploadException("There is no recorded data to send.");
  }
  Uint8List archive = await Isolate.run(() => _pack(files));

  double megabytes = archive.length / 1024 / 1024;
  onStatus?.call("Sending ${megabytes.toStringAsFixed(2)} MB…");
  Socket socket = await Socket.connect(host, port, timeout: connectTimeout);
  try {
    socket
      ..add(Uint8List(8)..buffer.asByteData().setUint64(0, archive.length))
      ..add(archive);
    await socket.flush();

    onStatus?.call("Waiting for the receiver to finish…");
    List<int> reply = await socket
        .fold<List<int>>(
          <int>[],
          (List<int> bytes, Uint8List chunk) => bytes..addAll(chunk),
        )
        .timeout(responseTimeout);
    String answer = String.fromCharCodes(reply);
    if (answer.isEmpty) {
      throw const UploadException(
        "No response from the receiver. Either it isn't running, or the "
        "connection was interrupted during the transfer.",
      );
    }
    if (!answer.startsWith("OK")) {
      throw UploadException("The receiver reported a problem: $answer");
    }
  } finally {
    await socket.close();
  }
}

/// Lists the files to upload as (relative path, absolute path) pairs.
Future<List<(String, String)>> _listFiles(
  Directory directory,
  bool Function(String relativePath)? include,
) async {
  if (!directory.existsSync()) {
    return <(String, String)>[];
  }
  String root = directory.absolute.path;
  List<(String, String)> files = <(String, String)>[];
  await for (FileSystemEntity entity in directory.absolute.list(
    recursive: true,
  )) {
    if (entity is! File) {
      continue;
    }
    String relativePath = entity.path
        .substring(root.length + 1)
        .replaceAll(Platform.pathSeparator, "/");
    if (include?.call(relativePath) ?? true) {
      files.add((relativePath, entity.path));
    }
  }
  return files;
}

/// Packs [files] into an uncompressed tar archive. Runs in a separate
/// isolate, so it may block.
Uint8List _pack(List<(String, String)> files) {
  Archive archive = Archive();
  for (var (String relativePath, String path) in files) {
    Uint8List bytes = File(path).readAsBytesSync();
    archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
  }
  return Uint8List.fromList(TarEncoder().encode(archive));
}
