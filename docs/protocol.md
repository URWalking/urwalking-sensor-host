# Wire protocol

How recordings get from the phone to a PC. The phone is always the client;
the PC runs a receiver (`tools/receiver/receiver.py` is the reference
implementation). Both connections are plain TCP, so they work over USB with
`adb reverse` as well as over Wi-Fi.

| Port | Direction | Used by | Purpose |
| --- | --- | --- | --- |
| 5001 | phone → PC | `TcpStreamSink` | live samples and clock sync while recording |
| 5000 | phone → PC, PC replies | `uploadDirectory` | the finished recording as one archive |

## Timestamps

All timestamps are `ts_ms`: integer milliseconds since the Unix epoch, taken
from the phone's `SensorClock`. This is the same value as the `phone_ts_ms`
column in the CSV files, so live and uploaded data line up.

The phone's clock and the PC's clock differ. The `clock` messages below let
the receiver measure that offset: `pc_time - ts_ms` at arrival (the result
also includes transfer latency, which is small and stable over USB).

## Live stream (port 5001)

UTF-8 text, one JSON object per line, lines separated by `\n`. Every
message has a `type`. Receivers must ignore messages with an unknown `type`
and unknown fields, so new message types can be added without breaking old
receivers.

### `hello`

Sent once, right after connecting.

```json
{"type":"hello","protocol":1}
```

### `clock`

Sent periodically (every 33 ms by default) for clock sync.

```json
{"type":"clock","ts_ms":1727700000123}
```

### `sample`

One sensor sample, sent as soon as it is recorded.

```json
{"type":"sample","sensor":"accelerometer","ts_ms":1727700000125,"values":{"acc_x":0.12,"acc_y":9.79,"acc_z":0.31}}
```

- `sensor`: the sensor id, e.g. `accelerometer`, `location`, `wifi`
- `values`: the sample's fields; each value is a number, string, boolean or
  `null` (non-finite numbers are sent as `null`). Every sample of a sensor
  has the same fields in the same order.

Samples recorded while the phone is not connected are dropped from the
live stream; they are still in the uploaded archive.

## Upload (port 5000)

Binary, one recording per connection:

1. The phone sends the archive length as an 8-byte unsigned big-endian
   integer, followed by that many bytes of an uncompressed tar archive.
2. The PC extracts it and replies with ASCII `OK`, or `ERROR: <message>`
   if something went wrong, then closes the connection.

The archive contains the recording directory: one `<sensor>_raw.csv` per
sensor at the top level (see `CsvSink`), and optionally an `images/` folder
with camera frames.

Recordings with camera frames easily reach hundreds of MB, so both sides
should stream: `uploadDirectory` writes the tar straight from the files to
the socket, and the reference receiver writes it to a temporary file before
extracting.
