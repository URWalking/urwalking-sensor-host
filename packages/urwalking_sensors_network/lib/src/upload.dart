import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

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
/// `docs/protocol.md`: the directory is sent to [host]:[port] as a tar
/// archive, and the receiver confirms with `OK`.
///
/// The archive is streamed directly from the files, so recordings of any
/// size can be uploaded without holding them in memory.
///
/// Files are included when [include] returns true for their path relative
/// to [directory] (with `/` as separator, e.g. `images/frame_1.jpg`); by
/// default everything is included. [onStatus] receives progress messages
/// for the user.
///
/// Throws an [UploadException] if there is nothing to upload or the
/// receiver reports an error, a [SocketException] if the receiver cannot be
/// reached, and a [TimeoutException] if it does not answer within
/// [responseTimeout] after the last byte was sent.
Future<void> uploadDirectory(
  Directory directory, {
  required String host,
  int port = 5000,
  bool Function(String relativePath)? include,
  void Function(String message)? onStatus,
  Duration connectTimeout = const Duration(seconds: 10),
  Duration responseTimeout = const Duration(minutes: 2),
}) async {
  onStatus?.call("Preparing data…");
  List<_TarEntry> entries = await _listFiles(directory, include);
  if (entries.isEmpty) {
    throw const UploadException("There is no recorded data to send.");
  }
  int archiveSize =
      entries.fold(0, (int sum, _TarEntry entry) => sum + entry.tarSize) +
      _endOfArchive.length;
  String totalMegabytes = _megabytes(archiveSize);

  Socket socket = await Socket.connect(host, port, timeout: connectTimeout);
  try {
    socket.add(Uint8List(8)..buffer.asByteData().setUint64(0, archiveSize));
    int sent = 0;
    for (_TarEntry entry in entries) {
      onStatus?.call("Sending ${_megabytes(sent)} of $totalMegabytes MB…");
      socket.add(entry.header());
      await socket.addStream(entry.file.openRead(0, entry.size));
      socket.add(Uint8List(entry.padding));
      sent += entry.tarSize;
    }
    socket.add(_endOfArchive);
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

String _megabytes(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);

Future<List<_TarEntry>> _listFiles(
  Directory directory,
  bool Function(String relativePath)? include,
) async {
  if (!directory.existsSync()) {
    return <_TarEntry>[];
  }
  String root = directory.absolute.path;
  List<_TarEntry> entries = <_TarEntry>[];
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
      FileStat stat = entity.statSync();
      entries.add(_TarEntry(entity, relativePath, stat.size, stat.modified));
    }
  }
  return entries;
}

/// Two empty blocks mark the end of a tar archive.
final Uint8List _endOfArchive = Uint8List(2 * _blockSize);

const int _blockSize = 512;

/// One file in a POSIX ustar archive: a 512-byte header, the content, and
/// zero padding up to a multiple of 512 bytes.
class _TarEntry {
  _TarEntry(this.file, this.path, this.size, this.modified);

  final File file;
  final String path;
  final int size;
  final DateTime modified;

  int get padding => (_blockSize - size % _blockSize) % _blockSize;

  int get tarSize => _blockSize + size + padding;

  Uint8List header() {
    Uint8List header = Uint8List(_blockSize);
    var (String prefix, String name) = _splitPath(path);
    _write(header, 0, 100, utf8.encode(name));
    _writeOctal(header, 100, 8, 420); // mode 0644
    _writeOctal(header, 108, 8, 0); // uid
    _writeOctal(header, 116, 8, 0); // gid
    _writeOctal(header, 124, 12, size);
    _writeOctal(header, 136, 12, modified.millisecondsSinceEpoch ~/ 1000);
    header[156] = 0x30; // type flag "0": regular file
    _write(header, 257, 6, ascii.encode("ustar\u0000"));
    _write(header, 263, 2, ascii.encode("00"));
    _write(header, 345, 155, utf8.encode(prefix));
    // The checksum is computed with the checksum field set to spaces.
    header.fillRange(148, 156, 0x20);
    int checksum = header.fold(0, (int sum, int byte) => sum + byte);
    _writeOctal(header, 148, 7, checksum);
    return header;
  }

  /// ustar stores paths longer than 100 bytes as prefix + "/" + name.
  static (String, String) _splitPath(String path) {
    if (utf8.encode(path).length <= 100) {
      return ("", path);
    }
    int split = path.lastIndexOf("/");
    while (split > 0) {
      String prefix = path.substring(0, split);
      String name = path.substring(split + 1);
      if (utf8.encode(prefix).length <= 155 &&
          utf8.encode(name).length <= 100) {
        return (prefix, name);
      }
      split = path.lastIndexOf("/", split - 1);
    }
    throw UploadException("File path too long to upload: $path");
  }

  static void _write(Uint8List header, int offset, int length, List<int> b) {
    header.setRange(offset, offset + b.length.clamp(0, length), b);
  }

  /// Writes [value] as zero-padded octal digits followed by a NUL byte.
  static void _writeOctal(Uint8List header, int offset, int length, int value) {
    String digits = value.toRadixString(8).padLeft(length - 1, "0");
    _write(header, offset, length, ascii.encode("$digits\u0000"));
  }
}
