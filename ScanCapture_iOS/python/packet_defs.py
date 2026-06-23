"""
packet_defs.py — SCAP protocol constants and packet parsers.

Wire format (little-endian):
  [4B magic "SCAP"] [1B type] [1B flags] [4B seq uint32] [4B payload_len uint32] [payload]
"""

import struct

MAGIC = b'SCAP'
HEADER_FMT = '<4sBBII'   # magic(4), type(1), flags(1), seq(4), payload_len(4)
HEADER_SIZE = 14


class PacketType:
    # Mac → iOS
    CMD_START       = 0x01
    CMD_STOP        = 0x02
    CMD_PING        = 0x03
    # iOS → Mac
    ACK             = 0x10
    DATA_POSE       = 0x11
    DATA_VIDEO      = 0x12
    DATA_DEPTH      = 0x13
    DATA_ACCEL      = 0x14
    DATA_GYRO       = 0x15
    DATA_MAGNETO    = 0x16
    DATA_FUSED_IMU  = 0x17
    DATA_BLUETOOTH  = 0x18
    DATA_LOCATION   = 0x19
    DATA_BARO       = 0x1A
    DATA_TIMESYNC   = 0x1B
    SESSION_START   = 0xFF
    SESSION_END     = 0xFE


def build_command(pkt_type: int, seq: int = 0, fps: int | None = None) -> bytes:
    """Build a command packet. For CMD_START, pass fps (1–60) to request a specific framerate."""
    payload = struct.pack('<H', fps) if fps is not None else b''
    header = struct.pack(HEADER_FMT, MAGIC, pkt_type, 0, seq, len(payload))
    return header + payload


def parse_header(data: bytes) -> dict:
    magic, ptype, flags, seq, payload_len = struct.unpack(HEADER_FMT, data[:HEADER_SIZE])
    if magic != MAGIC:
        raise ValueError(f"Bad magic: {magic!r}")
    return {'type': ptype, 'flags': flags, 'seq': seq, 'payload_len': payload_len}


# ---------------------------------------------------------------------------
# Payload parsers
# ---------------------------------------------------------------------------

def parse_pose(payload: bytes) -> dict:
    """DATA_POSE: 80-byte payload."""
    ts, status = struct.unpack_from('<qB', payload, 0)
    offset = 12  # 8 (ts) + 1 (status) + 3 (pad)
    tx, ty, tz = struct.unpack_from('<fff', payload, offset);  offset += 12
    qx, qy, qz, qw = struct.unpack_from('<ffff', payload, offset);  offset += 16
    w, h = struct.unpack_from('<II', payload, offset);  offset += 8
    fx, fy, cx, cy = struct.unpack_from('<ffff', payload, offset);  offset += 16
    exposure = struct.unpack_from('<q', payload, offset)[0]
    return dict(ts=ts, status=status,
                tx=tx, ty=ty, tz=tz,
                qx=qx, qy=qy, qz=qz, qw=qw,
                w=w, h=h, fx=fx, fy=fy, cx=cx, cy=cy,
                exposure=exposure)


def parse_imu3(payload: bytes) -> dict:
    """DATA_ACCEL / DATA_GYRO / DATA_MAGNETO: 20-byte payload."""
    ts, x, y, z = struct.unpack('<qfff', payload)
    return {'ts': ts, 'x': x, 'y': y, 'z': z}


def parse_fused_imu(payload: bytes) -> dict:
    """DATA_FUSED_IMU: 60-byte payload."""
    (ts,
     ax, ay, az,
     rx, ry, rz,
     mx, my, mz,
     gx, gy, gz,
     heading) = struct.unpack('<q13f', payload)
    return dict(ts=ts,
                ax=ax, ay=ay, az=az,
                rx=rx, ry=ry, rz=rz,
                mx=mx, my=my, mz=mz,
                gx=gx, gy=gy, gz=gz,
                heading=heading)


def parse_image(payload: bytes) -> dict:
    """DATA_VIDEO: timestamp(i64, iOS boot-relative µs) + jpeg_data(bytes)."""
    ts = struct.unpack_from('<q', payload, 0)[0]
    return {'ts': ts, 'jpeg_data': payload[8:]}


def parse_depth_header(payload: bytes) -> dict:
    """DATA_DEPTH: variable payload."""
    ts, w, h, bpr = struct.unpack_from('<qIII', payload, 0)
    offset = 20  # 8+4+4+4
    float_count = w * h
    float_bytes = float_count * 4
    depth_data = payload[offset:offset + float_bytes];  offset += float_bytes
    has_conf = payload[offset];  offset += 4  # 1 byte + 3 pad
    conf_len = struct.unpack_from('<I', payload, offset)[0];  offset += 4
    conf_png = payload[offset:offset + conf_len] if has_conf else b''
    return dict(ts=ts, w=w, h=h, bpr=bpr,
                depth_data=depth_data, conf_png=conf_png)


def parse_bluetooth(payload: bytes) -> dict:
    """DATA_BLUETOOTH: variable payload."""
    ts, rssi, name_len, uuid_len = struct.unpack_from('<qhHH', payload, 0)
    offset = 16  # 8+2+2+2+2pad
    name = payload[offset:offset + name_len].decode('utf-8', errors='replace')
    offset += name_len
    uuid = payload[offset:offset + uuid_len].decode('utf-8', errors='replace')
    return {'ts': ts, 'rssi': rssi, 'name': name, 'uuid': uuid}


def parse_location(payload: bytes) -> dict:
    """DATA_LOCATION: 48-byte payload."""
    ts, lat, lon, alt, hacc, vacc = struct.unpack('<qdddff', payload)
    return dict(ts=ts, lat=lat, lon=lon, alt=alt,
                horiz_acc=hacc, vert_acc=vacc)


def parse_baro(payload: bytes) -> dict:
    """DATA_BARO: 16-byte payload. pressure in kPa, relative_altitude in meters."""
    ts, pressure, rel_altitude = struct.unpack('<qff', payload)
    return {'ts': ts, 'pressure': pressure, 'relative_altitude': rel_altitude}


def parse_timesync(payload: bytes) -> dict:
    """DATA_TIMESYNC: 8-byte payload, phone timestamp µs since boot."""
    phone_ts = struct.unpack('<q', payload)[0]
    return {'phone_ts': phone_ts}


def parse_session_start(payload: bytes) -> dict:
    """SESSION_START: variable payload."""
    version, img_w, img_h, fps_num, fps_den, has_depth, name_len = \
        struct.unpack_from('<HIIIIBB', payload, 0)
    offset = 2 + 4 + 4 + 4 + 4 + 1 + 1  # = 20
    device_name = payload[offset:offset + name_len].decode('utf-8', errors='replace')
    fps = fps_num / fps_den if fps_den else 0
    return dict(version=version, img_w=img_w, img_h=img_h, fps=fps,
                has_depth=bool(has_depth), device_name=device_name)


def avcc_to_annexb(avcc_data: bytes) -> bytes:
    """Convert H.264 AVCC format to Annex B format for writing to .h264 file.

    AVCC:   [4-byte big-endian length][NAL data] ...
    Annex B: [0x00 0x00 0x00 0x01][NAL data] ...
    """
    START_CODE = b'\x00\x00\x00\x01'
    result = bytearray()
    offset = 0
    while offset + 4 <= len(avcc_data):
        nal_len = struct.unpack_from('>I', avcc_data, offset)[0]
        offset += 4
        if offset + nal_len > len(avcc_data):
            break
        result += START_CODE + avcc_data[offset:offset + nal_len]
        offset += nal_len
    return bytes(result)
