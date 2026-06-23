//
//  PacketBuilder.swift
//  ScanCapture
//
//  Serializes all sensor data into the SCAP binary packet protocol.
//  No network or file I/O here — only pure data packing.
//
//  Packet header (14 bytes, all multi-byte values little-endian):
//    [4B magic "SCAP"] [1B type] [1B flags] [4B seq uint32] [4B payload_len uint32]
//

import Foundation
import UIKit
import ARKit
import CoreMedia
import CoreImage
import CoreMotion
import CoreBluetooth
import CoreLocation

// MARK: - Packet Types

enum PacketType: UInt8 {
    // Mac → iOS commands
    case cmdStart      = 0x01
    case cmdStop       = 0x02
    case cmdPing       = 0x03
    // iOS → Mac data
    case ack           = 0x10
    case dataPose      = 0x11
    case dataVideo     = 0x12
    case dataDepth     = 0x13
    case dataAccel     = 0x14
    case dataGyro      = 0x15
    case dataMagneto   = 0x16
    case dataFusedIMU  = 0x17
    case dataBluetooth = 0x18
    case dataLocation  = 0x19
    case dataBaro      = 0x1A
    case dataTimesync  = 0x1B
    case dataCompass   = 0x1C
    case dataPedometer = 0x1D
    case dataWifi      = 0x1E
    case sessionStart  = 0xFF
    case sessionEnd    = 0xFE
}

// MARK: - PacketBuilder

enum PacketBuilder {

    static let magic: [UInt8] = [0x53, 0x43, 0x41, 0x50]  // "SCAP"

    // Per-type sequence counters (thread-safe via seqLock)
    private static var sequences = [UInt8: UInt32]()
    private static let seqLock = NSLock()

    private static func nextSequence(for type: PacketType) -> UInt32 {
        seqLock.lock(); defer { seqLock.unlock() }
        let seq = sequences[type.rawValue, default: 0]
        sequences[type.rawValue] = seq &+ 1
        return seq
    }

    static func buildPacket(type: PacketType, flags: UInt8 = 0, payload: Data) -> Data {
        var packet = Data(capacity: 14 + payload.count)
        packet.append(contentsOf: magic)
        packet.append(type.rawValue)
        packet.append(flags)
        var seq = nextSequence(for: type).littleEndian
        withUnsafeBytes(of: &seq) { packet.append(contentsOf: $0) }
        var len = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &len) { packet.append(contentsOf: $0) }
        packet.append(payload)
        return packet
    }

    // MARK: Helpers

    private static func appendLE<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private static func appendFloat32(_ data: inout Data, _ value: Float) {
        var v = value
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private static func appendFloat64(_ data: inout Data, _ value: Double) {
        var v = value
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    // MARK: - Per-Type Builders

    // DATA_POSE (80 bytes payload)
    // timestamp(i64), status(u8), pad(3), tx/ty/tz(f32×3), qx/qy/qz/qw(f32×4),
    // w/h(u32×2), fx/fy/cx/cy(f32×4), exposure(i64)
    static func posePacket(camera: ARCamera, timestamp: TimeInterval, state: String) -> Data {
        var payload = Data(capacity: 80)
        appendLE(&payload, timestampToInt(timestamp))                     // 8 bytes
        payload.append(statusCode(state))                                  // 1 byte
        payload.append(contentsOf: [0, 0, 0])                             // 3 bytes pad
        let tvec = camera.transform.columns.3
        appendFloat32(&payload, tvec.x); appendFloat32(&payload, tvec.y); appendFloat32(&payload, tvec.z)  // 12 bytes
        let q = simd_quatf(camera.transform).vector
        appendFloat32(&payload, q.x); appendFloat32(&payload, q.y)
        appendFloat32(&payload, q.z); appendFloat32(&payload, q.w)        // 16 bytes
        appendLE(&payload, UInt32(camera.imageResolution.width))
        appendLE(&payload, UInt32(camera.imageResolution.height))         // 8 bytes
        let K = camera.intrinsics
        appendFloat32(&payload, K[0][0]); appendFloat32(&payload, K[1][1])  // fx, fy
        appendFloat32(&payload, K[2][0]); appendFloat32(&payload, K[2][1])  // cx, cy  — 16 bytes
        appendLE(&payload, timestampToInt(camera.exposureDuration))       // 8 bytes
        return buildPacket(type: .dataPose, payload: payload)
    }

    private static func statusCode(_ state: String) -> UInt8 {
        switch state {
        case "Normal": return 0
        case "Initializing": return 1
        case "Limited": return 2
        default: return 3  // Not Available
        }
    }

    // DATA_ACCEL / DATA_GYRO / DATA_MAGNETO (20 bytes payload)
    // timestamp(i64), x/y/z(f32×3)
    static func accelPacket(data: CMAccelerometerData) -> Data {
        return imuPacket(type: .dataAccel, timestamp: data.timestamp,
                         x: Float(data.acceleration.x), y: Float(data.acceleration.y), z: Float(data.acceleration.z))
    }

    static func gyroPacket(data: CMGyroData) -> Data {
        return imuPacket(type: .dataGyro, timestamp: data.timestamp,
                         x: Float(data.rotationRate.x), y: Float(data.rotationRate.y), z: Float(data.rotationRate.z))
    }

    static func magnetoPacket(data: CMMagnetometerData) -> Data {
        return imuPacket(type: .dataMagneto, timestamp: data.timestamp,
                         x: Float(data.magneticField.x), y: Float(data.magneticField.y), z: Float(data.magneticField.z))
    }

    private static func imuPacket(type: PacketType, timestamp: TimeInterval, x: Float, y: Float, z: Float) -> Data {
        var payload = Data(capacity: 20)
        appendLE(&payload, timestampToInt(timestamp))
        appendFloat32(&payload, x); appendFloat32(&payload, y); appendFloat32(&payload, z)
        return buildPacket(type: type, payload: payload)
    }

    // DATA_FUSED_IMU (60 bytes payload)
    // timestamp(i64), user_accel(f32×3), rotation(f32×3), mag_field(f32×3), gravity(f32×3), heading(f32)
    static func fusedIMUPacket(data: CMDeviceMotion) -> Data {
        var payload = Data(capacity: 60)
        appendLE(&payload, timestampToInt(data.timestamp))
        appendFloat32(&payload, Float(data.userAcceleration.x))
        appendFloat32(&payload, Float(data.userAcceleration.y))
        appendFloat32(&payload, Float(data.userAcceleration.z))
        appendFloat32(&payload, Float(data.rotationRate.x))
        appendFloat32(&payload, Float(data.rotationRate.y))
        appendFloat32(&payload, Float(data.rotationRate.z))
        appendFloat32(&payload, Float(data.magneticField.field.x))
        appendFloat32(&payload, Float(data.magneticField.field.y))
        appendFloat32(&payload, Float(data.magneticField.field.z))
        appendFloat32(&payload, Float(data.gravity.x))
        appendFloat32(&payload, Float(data.gravity.y))
        appendFloat32(&payload, Float(data.gravity.z))
        appendFloat32(&payload, Float(data.heading))
        return buildPacket(type: .dataFusedIMU, payload: payload)
    }

    // DATA_VIDEO (variable) — JPEG image
    // timestamp(i64), jpeg_data(bytes)
    static func imagePacket(jpegData: Data, timestamp: TimeInterval) -> Data {
        var payload = Data(capacity: 8 + jpegData.count)
        appendLE(&payload, timestampToInt(timestamp))
        payload.append(jpegData)
        return buildPacket(type: .dataVideo, payload: payload)
    }

    // DATA_DEPTH (variable)
    // timestamp(i64), w(u32), h(u32), bpr(u32), depth_floats, has_conf(u8), pad(3), conf_len(u32), conf_png(bytes)
    @available(iOS 14.0, *)
    static func depthPacket(sceneDepth: ARDepthData, timestamp: TimeInterval) -> Data {
        let depthMap = sceneDepth.depthMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        let width  = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bpr    = CVPixelBufferGetBytesPerRow(depthMap)
        let addr   = CVPixelBufferGetBaseAddress(depthMap)!
        let depthData = Data(bytes: addr, count: bpr * height)
        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)

        var confPNGData = Data()
        var hasConf: UInt8 = 0
        if let confMap = sceneDepth.confidenceMap {
            let ciImage = CIImage(cvPixelBuffer: confMap)
            let ctx = CIContext()
            if let cgImage = ctx.createCGImage(ciImage, from: ciImage.extent) {
                let uiImage = UIImage(cgImage: cgImage)
                if let png = uiImage.pngData() {
                    confPNGData = png
                    hasConf = 1
                }
            }
        }

        var payload = Data(capacity: 8 + 12 + depthData.count + 8 + confPNGData.count)
        appendLE(&payload, timestampToInt(timestamp))
        appendLE(&payload, UInt32(width))
        appendLE(&payload, UInt32(height))
        appendLE(&payload, UInt32(bpr))
        payload.append(depthData)
        payload.append(hasConf)
        payload.append(contentsOf: [0, 0, 0])  // pad
        appendLE(&payload, UInt32(confPNGData.count))
        payload.append(confPNGData)
        return buildPacket(type: .dataDepth, payload: payload)
    }

    // DATA_BLUETOOTH (variable)
    // timestamp(i64), rssi(i16), name_len(u16), uuid_len(u16), pad(2), name(utf8), uuid(utf8)
    static func bluetoothPacket(peripheral: CBPeripheral, rssi: NSNumber) -> Data {
        let nameStr = (peripheral.name ?? "unknown").replacingOccurrences(of: ",", with: "")
        let uuidStr = peripheral.identifier.uuidString
        let nameBytes = nameStr.data(using: .utf8) ?? Data()
        let uuidBytes = uuidStr.data(using: .utf8) ?? Data()

        var payload = Data(capacity: 8 + 2 + 2 + 2 + 2 + nameBytes.count + uuidBytes.count)
        appendLE(&payload, timestampToInt(ProcessInfo.processInfo.systemUptime))
        appendLE(&payload, Int16(truncatingIfNeeded: rssi.intValue))
        appendLE(&payload, UInt16(nameBytes.count))
        appendLE(&payload, UInt16(uuidBytes.count))
        payload.append(contentsOf: [0, 0])  // pad
        payload.append(nameBytes)
        payload.append(uuidBytes)
        return buildPacket(type: .dataBluetooth, payload: payload)
    }

    // DATA_BARO (16 bytes)
    // timestamp(i64), pressure(f32 kPa), relative_altitude(f32 m)
    static func baroPacket(pressure: Double, relativeAltitude: Double, timestamp: TimeInterval) -> Data {
        var payload = Data(capacity: 16)
        appendLE(&payload, timestampToInt(timestamp))
        appendFloat32(&payload, Float(pressure))
        appendFloat32(&payload, Float(relativeAltitude))
        return buildPacket(type: .dataBaro, payload: payload)
    }

    // DATA_LOCATION (48 bytes)
    // timestamp(i64), lat/lon/alt(f64×3), horiz_acc/vert_acc(f32×2)
    static func locationPacket(location: CLLocation) -> Data {
        let bootDate = Date() - ProcessInfo.processInfo.systemUptime
        var payload = Data(capacity: 48)
        appendLE(&payload, timestampToInt(location.timestamp.timeIntervalSince(bootDate)))
        appendFloat64(&payload, location.coordinate.latitude)
        appendFloat64(&payload, location.coordinate.longitude)
        appendFloat64(&payload, location.altitude)
        appendFloat32(&payload, Float(location.horizontalAccuracy))
        appendFloat32(&payload, Float(location.verticalAccuracy))
        return buildPacket(type: .dataLocation, payload: payload)
    }

    // SESSION_START
    // version(u16), image_width(u32), image_height(u32), fps_num(u32), fps_den(u32),
    // has_depth(u8), device_name_len(u16), device_name(utf8)
    static func sessionStartPacket(imageWidth: Int, imageHeight: Int, fps: Double, hasDepth: Bool) -> Data {
        let deviceName = UIDevice.current.name
        let nameBytes = deviceName.data(using: .utf8) ?? Data()

        var payload = Data()
        appendLE(&payload, UInt16(1))                // protocol version
        appendLE(&payload, UInt32(imageWidth))
        appendLE(&payload, UInt32(imageHeight))
        appendLE(&payload, UInt32(Int(fps * 1000)))  // fps_num (milli-fps for precision)
        appendLE(&payload, UInt32(1000))             // fps_den
        payload.append(hasDepth ? 1 : 0)
        appendLE(&payload, UInt16(nameBytes.count))
        payload.append(nameBytes)
        return buildPacket(type: .sessionStart, payload: payload)
    }

    // DATA_TIMESYNC (8 bytes) — phone timestamp only; PC records arrival time alongside it
    static func timeSyncPacket(timestamp: TimeInterval) -> Data {
        var payload = Data(capacity: 8)
        appendLE(&payload, timestampToInt(timestamp))
        return buildPacket(type: .dataTimesync, payload: payload)
    }

    // SESSION_END — no payload
    static func sessionEndPacket() -> Data {
        return buildPacket(type: .sessionEnd, payload: Data())
    }

    // ACK — 1 byte payload: 0x00 = ok
    static func ackPacket(ok: Bool) -> Data {
        return buildPacket(type: .ack, payload: Data([ok ? 0x00 : 0x01]))
    }

    // DATA_COMPASS (56 bytes)
    // timestamp(i64), magnetic_heading/true_heading/heading_accuracy(f64×3), x/y/z(f64×3)
    static func compassPacket(heading: CLHeading) -> Data {
        let bootDate = Date() - ProcessInfo.processInfo.systemUptime
        var payload = Data(capacity: 56)
        appendLE(&payload, timestampToInt(heading.timestamp.timeIntervalSince(bootDate)))
        appendFloat64(&payload, heading.magneticHeading)
        appendFloat64(&payload, heading.trueHeading)
        appendFloat64(&payload, heading.headingAccuracy)
        appendFloat64(&payload, heading.x)
        appendFloat64(&payload, heading.y)
        appendFloat64(&payload, heading.z)
        return buildPacket(type: .dataCompass, payload: payload)
    }

    // DATA_PEDOMETER (40 bytes)
    // timestamp(i64), steps(i64), distance/avg_pace/current_pace/cadence(f32×4),
    // floors_asc/floors_desc(i32×2)
    static func pedometerPacket(data: CMPedometerData, bootDate: Date) -> Data {
        var payload = Data(capacity: 40)
        appendLE(&payload, timestampToInt(data.endDate.timeIntervalSince(bootDate)))
        appendLE(&payload, data.numberOfSteps.int64Value)
        appendFloat32(&payload, Float(data.distance?.doubleValue ?? 0))
        appendFloat32(&payload, Float(data.averageActivePace?.doubleValue ?? -1))
        appendFloat32(&payload, Float(data.currentPace?.doubleValue ?? -1))
        appendFloat32(&payload, Float(data.currentCadence?.doubleValue ?? -1))
        appendLE(&payload, Int32(data.floorsAscended?.intValue ?? 0))
        appendLE(&payload, Int32(data.floorsDescended?.intValue ?? 0))
        return buildPacket(type: .dataPedometer, payload: payload)
    }

    // DATA_WIFI (variable)
    // timestamp(i64), ssid_len(u16), bssid_len(u16), ssid(utf8), bssid(utf8)
    static func wifiPacket(ssid: String, bssid: String) -> Data {
        let ssidBytes  = ssid.data(using: .utf8)  ?? Data()
        let bssidBytes = bssid.data(using: .utf8) ?? Data()
        var payload = Data(capacity: 8 + 2 + 2 + ssidBytes.count + bssidBytes.count)
        appendLE(&payload, timestampToInt(ProcessInfo.processInfo.systemUptime))
        appendLE(&payload, UInt16(ssidBytes.count))
        appendLE(&payload, UInt16(bssidBytes.count))
        payload.append(ssidBytes)
        payload.append(bssidBytes)
        return buildPacket(type: .dataWifi, payload: payload)
    }
}
