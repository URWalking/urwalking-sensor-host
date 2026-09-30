/// Sends `urwalking_sensors` recordings to a PC: live with [TcpStreamSink],
/// or as an archive after recording with [uploadDirectory].
///
/// The wire format is described in `docs/protocol.md`;
/// `tools/receiver/receiver.py` is the reference receiver.
library;

import "package:urwalking_sensors_network/src/tcp_stream_sink.dart";
import "package:urwalking_sensors_network/src/upload.dart";

export "src/tcp_stream_sink.dart";
export "src/upload.dart";
