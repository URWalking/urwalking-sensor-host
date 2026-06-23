//
//  IO.swift
//  ScanCapture
//
//  Created by Paul-Edouard Sarlin on 30.05.21.
//

import Foundation
import AVFoundation
import os.log
import ARKit
import MobileCoreServices  // for ImageI/O
import CoreMotion
import CoreBluetooth
import CoreLocation
import SystemConfiguration.CaptiveNetwork


func timestampToInt(_ timestamp: TimeInterval) -> Int64 {
    return Int64(round(timestamp * 1000000))  // second to microsecond
}


class ImageStreamer {
    var path: URL!
    var isInitialized: Bool = false
    let timeScale: Int32 = Int32(timestampToInt(1.0))  // microseconds
    private var _assetWriter: AVAssetWriter?
    private var _assetWriterInput: AVAssetWriterInput?
    private var _adapter: AVAssetWriterInputPixelBufferAdaptor?
    var counter: Int64 = 0
    
    init?(outDir: URL) {
        path = outDir.appendingPathComponent("images.mp4")
    }

    func initializeStream(buffer: CVPixelBuffer, timestamp: TimeInterval) {
        let writer = try! AVAssetWriter(outputURL: path, fileType: .mp4)
        writer.movieFragmentInterval = CMTimeMake(value: timestampToInt(1.0), timescale: timeScale)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: CVPixelBufferGetWidthOfPlane(buffer, 0),
            AVVideoHeightKey: CVPixelBufferGetHeightOfPlane(buffer, 0),
            AVVideoCompressionPropertiesKey: [
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.mediaTimeScale = timeScale
        input.expectsMediaDataInRealTime = true
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        if writer.canAdd(input) {
            writer.add(input)
        } else {
            os_log("Cannot initialize image stream", type:.error)
        }
        writer.startWriting()
        writer.startSession(atSourceTime: CMTimeMake(value: timestampToInt(timestamp), timescale:timeScale))
        
        _assetWriter = writer
        _assetWriterInput = input
        _adapter = adapter
        isInitialized = true
        counter = 0
    }
    
    func resetStream() {
        isInitialized = false
        _assetWriter = nil
        _assetWriterInput = nil
        _adapter = nil
    }
    
    func write(buffer: CVPixelBuffer, timestamp: TimeInterval) {
        if !isInitialized {
            initializeStream(buffer: buffer, timestamp: timestamp)
        }
        guard _assetWriterInput?.isReadyForMoreMediaData == true else {
            os_log("ImageStreamer: encoder not ready, dropping frame %lld", counter)
            return
        }
        let time = CMTimeMake(value: timestampToInt(timestamp), timescale: timeScale)
        if !_adapter!.append(buffer, withPresentationTime: time) {
            os_log("Could not append image frame %lld", type: .error, counter)
        }
        counter += 1
    }
    
    func finish() {
        os_log("Finishing the image stream, status: %d, ready? %d", _assetWriter!.status.rawValue, _assetWriterInput!.isReadyForMoreMediaData ? 1 : 0)
        _assetWriterInput?.markAsFinished()
        _assetWriter?.finishWriting { [weak self] in
            self?.resetStream()
        }
    }
}


class ImageWriter {
    var outDir: URL!
    let imageContext = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!)
    //    let imageContext = CIContext(options: nil)
    
    init?(outDir: URL) {
        self.outDir = outDir
        do {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            os_log("Cannot create the image directory: %@", type:.error, error.localizedDescription)
            return nil
        }
    }
    
    private func imageBufferToUIImage(buffer: CVPixelBuffer) -> UIImage {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let cgImage = self.imageContext.createCGImage(ciImage, from: ciImage.extent)
        let image = UIImage(cgImage: cgImage!)
        return image
    }

    func write(buffer: CVPixelBuffer, timestamp: TimeInterval) {
        let image = self.imageBufferToUIImage(buffer: buffer)
        if let data = image.jpegData(compressionQuality: 0.5) {
            let imagePath = outDir.appendingPathComponent(String(format: "%lld.jpg", timestampToInt(timestamp)))
            do {
                try data.write(to: imagePath)
            } catch {
                os_log("Cannot write image: %@", type:.error, error.localizedDescription)
            }
        }
    }
    
    // Apparently slower than using UIImage.jpegData
    func write2(buffer: CVPixelBuffer, timestamp: TimeInterval) {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let cgImage = self.imageContext.createCGImage(ciImage, from: ciImage.extent)
        
        let imagePath = outDir.appendingPathComponent(String(format: "%lld.jpg", timestampToInt(timestamp)))
        let options: NSDictionary = [kCGImageDestinationLossyCompressionQuality: 0.5]
        let myImageDest = CGImageDestinationCreateWithURL(imagePath as CFURL, kUTTypeJPEG, 1, nil)!
        CGImageDestinationAddImage(myImageDest, cgImage!, options)
        CGImageDestinationFinalize(myImageDest)
    }
    
    @available(iOS 14.0, *)
    func writeDepth(sceneDepth: ARDepthData, timestamp: TimeInterval) {
        let depthMap = sceneDepth.depthMap;
        CVPixelBufferLockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
        let addr = CVPixelBufferGetBaseAddress(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bpr = CVPixelBufferGetBytesPerRow(depthMap)
        let data = Data(bytes: addr!, count: (bpr*height))
        let fileName = String(format: "%lld.bin", timestampToInt(timestamp))
        let filePath = self.outDir.appendingPathComponent(fileName)
        do {
           try data.write(to: filePath)
        } catch {
            os_log("Cannot write depth map: %@", type:.error, error.localizedDescription)
        }
        CVPixelBufferUnlockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
        
        if (sceneDepth.confidenceMap != nil) {
            let confidence = self.imageBufferToUIImage(buffer: sceneDepth.confidenceMap!)
            if let data = confidence.pngData() {
                let fileName = String(format: "%lld.confidence.png", timestampToInt(timestamp))
                let imagePath = self.outDir.appendingPathComponent(fileName)
                do {
                    try data.write(to: imagePath)
                } catch {
                    os_log("Cannot write confidence: %@", type:.error, error.localizedDescription)
                }
            }
        }
    }
}

class PoseWriter {
    var file: FileHandle!
    let filename = "poses.txt"
    let header = "# timestamp, status, tx, ty, tz, qx, qy, qz, qw, w, h, fx, fy, cx, cy, exposure\n"
    let template = "%lld, %@, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %u, %u, %.6f, %.6f, %.6f, %.6f, %lld\n"
    
    init?(outDir: URL) {
        let device = UIDevice.current  // add some info about the device used to record
        let device_str = String(format: "# %@ %@ %@ %@", device.name, device.systemName, device.systemVersion, device.model)
        let header_ = device_str + "\n" + header
        
        let fileURL = outDir.appendingPathComponent(filename)
        if (!FileManager.default.createFile(atPath: fileURL.path, contents: header_.data(using: String.Encoding.utf8), attributes: nil)) {
            os_log("Cannot create the pose file at %@", type:.error, fileURL.path)
            return nil
        }
        do {
            try file = FileHandle(forWritingTo: fileURL)
        } catch {
            os_log("Cannot create the pose file: %@", type:.error, error.localizedDescription)
            return nil
        }
        file.seekToEndOfFile()
    }
    
    func write(camera: ARCamera, timestamp: TimeInterval, state: String) {
        let tvec = camera.transform.columns.3
        let qvec = simd_quatf(camera.transform).vector
        let width = UInt32(camera.imageResolution.width)
        let height = UInt32(camera.imageResolution.height)
        let K = camera.intrinsics
        let poseData = String(
            format: template,
            timestampToInt(timestamp), state, tvec.x, tvec.y, tvec.z, qvec.x, qvec.y, qvec.z, qvec.w,
            width, height, K[0][0], K[1][1], K[2][0], K[2][1],
            timestampToInt(camera.exposureDuration))
        if let poseDataOut = poseData.data(using: .utf8) {
            file!.write(poseDataOut)
        } else {
            os_log("Failed to format to the pose string: %@", type: .fault, poseData)
        }
    }
    
    func finish() {
        file.closeFile()
        file = nil
    }
}

class AccelWriter {
    var file: FileHandle!
    var manager: CMMotionManager!
    let filename = "accelerometer.txt"
    let header = "# timestamp, ax, ay, az\n"
    let template = "%lld, %.6f, %.6f, %.6f\n"
    
    init?(outDir: URL, manager: CMMotionManager, freq: Double) {
        if !manager.isAccelerometerAvailable { return nil }
        manager.accelerometerUpdateInterval = 1.0 / freq
        self.manager = manager
        
        let fileURL = outDir.appendingPathComponent(filename)
        if (!FileManager.default.createFile(atPath: fileURL.path, contents: header.data(using: String.Encoding.utf8),
                                            attributes: nil)) {
            os_log("Cannot create the accelerometer file at %@", type:.error, fileURL.path)
            return nil
        }
        do {
            try file = FileHandle(forWritingTo: fileURL)
        } catch {
            os_log("Cannot create the accelerometer file: %@", type:.error, error.localizedDescription)
            return nil
        }
        file.seekToEndOfFile()
    }
    
    func start(queue: OperationQueue) {
        manager.startAccelerometerUpdates(to: queue, withHandler: { (inData, error) in
            if let data = inData {  // if valid
                let strData = String(
                    format: self.template,
                    timestampToInt(data.timestamp),
                    data.acceleration.x, data.acceleration.y, data.acceleration.z)
                if let outData = strData.data(using: .utf8) {
                    self.file!.write(outData)
                } else {
                    os_log("Failed to format to the accelerometer string: %@", type: .fault, strData)
                }
            }
        })
    }
    
    func finish() {
        manager.stopAccelerometerUpdates()
        file.closeFile()
        file = nil
    }
}

class GyroWriter {
    var file: FileHandle!
    var manager: CMMotionManager!
    let filename = "gyroscope.txt"
    let header = "# timestamp, rx, ry, rz\n"
    let template = "%lld, %.6f, %.6f, %.6f\n"
    
    init?(outDir: URL, manager: CMMotionManager, freq: Double) {
        if !manager.isGyroAvailable { return nil }
        manager.gyroUpdateInterval = 1.0 / freq
        self.manager = manager
        
        let fileURL = outDir.appendingPathComponent(filename)
        if (!FileManager.default.createFile(atPath: fileURL.path, contents: header.data(using: String.Encoding.utf8),
                                            attributes: nil)) {
            os_log("Cannot create the gyroscope file at %@", type:.error, fileURL.path)
            return nil
        }
        do {
            try file = FileHandle(forWritingTo: fileURL)
        } catch {
            os_log("Cannot create the gyroscope file: %@", type:.error, error.localizedDescription)
            return nil
        }
        file.seekToEndOfFile()
    }
    
    func start(queue: OperationQueue) {
        manager.startGyroUpdates(to: queue, withHandler: { (inData, error) in
            if let data = inData {  // if valid
                let strData = String(
                    format: self.template,
                    timestampToInt(data.timestamp),
                    data.rotationRate.x, data.rotationRate.y, data.rotationRate.z)
                if let outData = strData.data(using: .utf8) {
                    self.file!.write(outData)
                } else {
                    os_log("Failed to format to the gyroscope string: %@", type: .fault, strData)
                }
            }
        })
    }
    
    func finish() {
        manager.stopGyroUpdates()
        file.closeFile()
        file = nil
    }
}

class MagnetoWriter {
    var file: FileHandle!
    var manager: CMMotionManager!
    let filename = "magnetometer.txt"
    let header = "# timestamp, mx, my, mz\n"
    let template = "%lld, %.6f, %.6f, %.6f\n"
    
    init?(outDir: URL, manager: CMMotionManager, freq: Double) {
        if !manager.isMagnetometerAvailable { return nil }
        manager.magnetometerUpdateInterval = 1.0 / freq
        self.manager = manager
        
        let fileURL = outDir.appendingPathComponent(filename)
        if (!FileManager.default.createFile(atPath: fileURL.path, contents: header.data(using: String.Encoding.utf8),
                                            attributes: nil)) {
            os_log("Cannot create the magnetometer file at %@", type:.error, fileURL.path)
            return nil
        }
        do {
            try file = FileHandle(forWritingTo: fileURL)
        } catch {
            os_log("Cannot create the magnetometer file: %@", type:.error, error.localizedDescription)
            return nil
        }
        file.seekToEndOfFile()
    }
    
    func start(queue: OperationQueue) {
        manager.startMagnetometerUpdates(to: queue, withHandler: { (inData, error) in
            if let data = inData {  // if valid
                let strData = String(
                    format: self.template,
                    timestampToInt(data.timestamp),
                    data.magneticField.x, data.magneticField.y, data.magneticField.z)
                if let outData = strData.data(using: .utf8) {
                    self.file!.write(outData)
                } else {
                    os_log("Failed to format to the magnetometer string: %@", type: .fault, strData)
                }
            }
        })
    }
    
    func finish() {
        manager.stopMagnetometerUpdates()
        file.closeFile()
        file = nil
    }
}

class FusedMotionWriter {
    var file: FileHandle!
    // Separate CMMotionManager so startDeviceMotionUpdates doesn't kill the raw
    // sensor callbacks (startAccelerometerUpdates etc.) on the shared instance.
    private let fusedManager = CMMotionManager()
    let filename = "fused_imu.txt"
    let header = "# timestamp, ax, ay, az, rx, ry, rz, mx, my, mz, gx, gy, gz, heading\n"
    let template = "%lld, " + Array(repeating: "%.6f", count: 13).joined(separator: ", ") + "\n"

    init?(outDir: URL, manager: CMMotionManager, freq: Double) {
        if !manager.isDeviceMotionAvailable { return nil }
        fusedManager.deviceMotionUpdateInterval = 1.0 / freq

        let fileURL = outDir.appendingPathComponent(filename)
        if (!FileManager.default.createFile(atPath: fileURL.path, contents: header.data(using: String.Encoding.utf8),
                                            attributes: nil)) {
            os_log("Cannot create the fused motion file at %@", type:.error, fileURL.path)
            return nil
        }
        do {
            try file = FileHandle(forWritingTo: fileURL)
        } catch {
            os_log("Cannot create the fused motion file: %@", type:.error, error.localizedDescription)
            return nil
        }
        file.seekToEndOfFile()
    }

    func start(queue: OperationQueue) {
        fusedManager.startDeviceMotionUpdates(using: CMAttitudeReferenceFrame.xTrueNorthZVertical, to: queue, withHandler: { (inData, error) in
            if let data = inData {  // if valid
                let strData = String(
                    format: self.template,
                    timestampToInt(data.timestamp),
                    data.userAcceleration.x, data.userAcceleration.y, data.userAcceleration.z,
                    data.rotationRate.x, data.rotationRate.y, data.rotationRate.z,
                    data.magneticField.field.x, data.magneticField.field.y, data.magneticField.field.z,
                    data.gravity.x, data.gravity.y, data.gravity.z,
                    data.heading)
                if let outData = strData.data(using: .utf8) {
                    self.file!.write(outData)
                } else {
                    os_log("Failed to format to the fused motion string: %@", type: .fault, strData)
                }
            }
        })
    }

    func finish() {
        fusedManager.stopDeviceMotionUpdates()
        file.closeFile()
        file = nil
    }
}

class MotionWriter {
    var accelWriter: AccelWriter!
    var gyroWriter: GyroWriter!
    var magnetoWriter: MagnetoWriter!
    var fusedWriter: FusedMotionWriter!
    var manager: CMMotionManager
    var queue: OperationQueue!
    
    init?(outDir: URL, manager: CMMotionManager, freq: Double) {
        guard let accelWriter = AccelWriter(outDir: outDir, manager: manager, freq: freq) else {return nil}
        self.accelWriter = accelWriter
        guard let gyroWriter = GyroWriter(outDir: outDir, manager: manager, freq: freq) else {return nil}
        self.gyroWriter = gyroWriter
        guard let magnetoWriter = MagnetoWriter(outDir: outDir, manager: manager, freq: freq) else {return nil}
        self.magnetoWriter = magnetoWriter
        guard let fusedWriter = FusedMotionWriter(outDir: outDir, manager: manager, freq: freq) else {return nil}
        self.fusedWriter = fusedWriter
        self.manager = manager
    }
    
    func start() {
        queue = OperationQueue()
        queue.name = "IMU queue"
        queue.maxConcurrentOperationCount = 1
        
        accelWriter!.start(queue: queue)
        gyroWriter!.start(queue: queue)
        magnetoWriter!.start(queue: queue)
        fusedWriter!.start(queue: queue)
    }
    
    func finish() {
        manager.stopAccelerometerUpdates()
        manager.stopGyroUpdates()
        manager.stopMagnetometerUpdates()
        queue.waitUntilAllOperationsAreFinished()
        accelWriter.finish()
        gyroWriter.finish()
        magnetoWriter.finish()
        fusedWriter.finish()  // stops fusedManager internally
    }
}

class BluetoothWriter {
    var file: FileHandle!
    let filename = "bluetooth.txt"
    let header = "# timestamp, name, uuid, rssi\n"
    let template = "%lld, %@, %@, %@\n"
    
    init?(outDir: URL) {
        let fileURL = outDir.appendingPathComponent(filename)
        if (!FileManager.default.createFile(atPath: fileURL.path, contents: header.data(using: String.Encoding.utf8), attributes: nil)) {
            os_log("Cannot create the bluetooth file at %@", type:.error, fileURL.path)
            return nil
        }
        do {
            try file = FileHandle(forWritingTo: fileURL)
        } catch {
            os_log("Cannot create the bluetooth file: %@", type:.error, error.localizedDescription)
            return nil
        }
        file.seekToEndOfFile()
    }
    
    func write(peripheral: CBPeripheral, rssi: NSNumber) {
        let name = peripheral.name ?? "unkown"
        let strData = String(
            format: template,
            timestampToInt(ProcessInfo.processInfo.systemUptime),
            name.replacingOccurrences(of: ",", with: ""),
            peripheral.identifier.uuidString,
            rssi)
        if let outData = strData.data(using: .utf8) {
            file!.write(outData)
        } else {
            os_log("Failed to format to the bluetooth string: %@", type: .fault, strData)
        }
    }
    
    func finish() {
        file.closeFile()
        file = nil
    }
}

// MARK: - Streaming Senders
// These classes mirror the file-writer classes above but send data over StreamingServer
// instead of writing to disk. All file-writer classes above are left untouched.

class PoseStreamer {
    weak var server: StreamingServer?

    func send(camera: ARCamera, timestamp: TimeInterval, state: String) {
        let packet = PacketBuilder.posePacket(camera: camera, timestamp: timestamp, state: state)
        server?.send(packet)
    }
}

class AccelStreamer {
    weak var server: StreamingServer?
    var manager: CMMotionManager!

    func start(manager: CMMotionManager, freq: Double, queue: OperationQueue) {
        self.manager = manager
        manager.accelerometerUpdateInterval = 1.0 / freq
        manager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let data = data, let self = self else { return }
            self.server?.send(PacketBuilder.accelPacket(data: data), dropIfBusy: true)
        }
    }

    func finish() { manager?.stopAccelerometerUpdates() }
}

class GyroStreamer {
    weak var server: StreamingServer?
    var manager: CMMotionManager!

    func start(manager: CMMotionManager, freq: Double, queue: OperationQueue) {
        self.manager = manager
        manager.gyroUpdateInterval = 1.0 / freq
        manager.startGyroUpdates(to: queue) { [weak self] data, _ in
            guard let data = data, let self = self else { return }
            self.server?.send(PacketBuilder.gyroPacket(data: data), dropIfBusy: true)
        }
    }

    func finish() { manager?.stopGyroUpdates() }
}

class MagnetoStreamer {
    weak var server: StreamingServer?
    var manager: CMMotionManager!

    func start(manager: CMMotionManager, freq: Double, queue: OperationQueue) {
        self.manager = manager
        manager.magnetometerUpdateInterval = 1.0 / freq
        manager.startMagnetometerUpdates(to: queue) { [weak self] data, _ in
            guard let data = data, let self = self else { return }
            self.server?.send(PacketBuilder.magnetoPacket(data: data), dropIfBusy: true)
        }
    }

    func finish() { manager?.stopMagnetometerUpdates() }
}

class FusedIMUStreamer {
    weak var server: StreamingServer?
    private let fusedManager = CMMotionManager()

    func start(manager: CMMotionManager, freq: Double, queue: OperationQueue) {
        fusedManager.deviceMotionUpdateInterval = 1.0 / freq
        fusedManager.startDeviceMotionUpdates(
            using: CMAttitudeReferenceFrame.xTrueNorthZVertical, to: queue) { [weak self] data, _ in
            guard let data = data, let self = self else { return }
            self.server?.send(PacketBuilder.fusedIMUPacket(data: data), dropIfBusy: true)
        }
    }

    func finish() { fusedManager.stopDeviceMotionUpdates() }
}

/// Composite: owns all 4 IMU streamers, starts/stops them on a shared serial queue.
class MotionStreamer {
    private let accel = AccelStreamer()
    private let gyro = GyroStreamer()
    private let magneto = MagnetoStreamer()
    private let fused = FusedIMUStreamer()
    private var queue: OperationQueue!

    init(server: StreamingServer) {
        accel.server = server
        gyro.server = server
        magneto.server = server
        fused.server = server
    }

    func start(manager: CMMotionManager, freq: Double) {
        queue = OperationQueue()
        queue.name = "IMU stream queue"
        queue.maxConcurrentOperationCount = 1

        if manager.isAccelerometerAvailable { accel.start(manager: manager, freq: freq, queue: queue) }
        if manager.isGyroAvailable          { gyro.start(manager: manager, freq: freq, queue: queue) }
        if manager.isMagnetometerAvailable  { magneto.start(manager: manager, freq: freq, queue: queue) }
        if manager.isDeviceMotionAvailable  { fused.start(manager: manager, freq: freq, queue: queue) }
    }

    func finish(manager: CMMotionManager) {
        accel.finish()
        gyro.finish()
        magneto.finish()
        fused.finish()
        queue.waitUntilAllOperationsAreFinished()
    }
}

class BluetoothStreamer {
    weak var server: StreamingServer?

    func send(peripheral: CBPeripheral, rssi: NSNumber) {
        let packet = PacketBuilder.bluetoothPacket(peripheral: peripheral, rssi: rssi)
        server?.send(packet)
    }
}

class LocationStreamer {
    weak var server: StreamingServer?

    func send(locations: [CLLocation]) {
        for location in locations {
            server?.send(PacketBuilder.locationPacket(location: location))
        }
    }
}

class DepthStreamer {
    weak var server: StreamingServer?

    @available(iOS 14.0, *)
    func send(sceneDepth: ARDepthData, timestamp: TimeInterval) {
        let packet = PacketBuilder.depthPacket(sceneDepth: sceneDepth, timestamp: timestamp)
        server?.send(packet)
    }
}

class BaroStreamer {
    weak var server: StreamingServer?
    private let altimeter = CMAltimeter()
    private var startUptime: TimeInterval = 0

    func start(queue: OperationQueue) {
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            os_log("Barometer not available on this device.")
            return
        }
        startUptime = ProcessInfo.processInfo.systemUptime
        altimeter.startRelativeAltitudeUpdates(to: queue) { [weak self] data, error in
            guard let data = data, let self = self else { return }
            // CMAltimeter has no absolute timestamp — derive from elapsed time since start
            let timestamp = self.startUptime + data.timestamp
            let packet = PacketBuilder.baroPacket(
                pressure: data.pressure.doubleValue,           // kPa
                relativeAltitude: data.relativeAltitude.doubleValue,  // meters
                timestamp: timestamp)
            self.server?.send(packet)
        }
    }

    func finish() {
        altimeter.stopRelativeAltitudeUpdates()
    }
}

// Keep the original LocationWriter below:
class LocationWriter {
    var file: FileHandle!
    let filename = "location.txt"
    let header = "# timestamp, lat, long, z, sigma_xy, sigma_z\n"
    let template = "%lld, %.6f, %.6f, %.6f, %.6f, %.6f\n"

    init?(outDir: URL) {
        let fileURL = outDir.appendingPathComponent(filename)
        if (!FileManager.default.createFile(atPath: fileURL.path, contents: header.data(using: String.Encoding.utf8), attributes: nil)) {
            os_log("Cannot create the location file at %@", type:.error, fileURL.path)
            return nil
        }
        do {
            try file = FileHandle(forWritingTo: fileURL)
        } catch {
            os_log("Cannot create the location file: %@", type:.error, error.localizedDescription)
            return nil
        }
        file.seekToEndOfFile()
    }

    func write(location: CLLocation) {
        let bootDate = Date() - ProcessInfo.processInfo.systemUptime
        let strData = String(
            format: template,
            timestampToInt(location.timestamp.timeIntervalSince(bootDate)),
            location.coordinate.latitude,
            location.coordinate.longitude,
            location.altitude,
            location.horizontalAccuracy,
            location.verticalAccuracy)
        if let outData = strData.data(using: .utf8) {
            file!.write(outData)
        } else {
            os_log("Failed to format to the location string: %@", type: .fault, strData)
        }
    }
    
    func write_multiple(locations: [CLLocation]) {
        for location in locations {
            write(location: location)
        }
    }

    func finish() {
        file.closeFile()
        file = nil
    }
}

class BaroWriter {
    var file: FileHandle!
    let filename = "barometer.txt"
    let header = "# timestamp, pressure_kPa, relative_altitude_m\n"
    let template = "%lld, %.4f, %.4f\n"
    private let altimeter = CMAltimeter()

    init?(outDir: URL) {
        let fileURL = outDir.appendingPathComponent(filename)
        if !FileManager.default.createFile(atPath: fileURL.path, contents: header.data(using: .utf8), attributes: nil) {
            os_log("Cannot create the barometer file at %@", type: .error, fileURL.path)
            return nil
        }
        do {
            file = try FileHandle(forWritingTo: fileURL)
        } catch {
            os_log("Cannot create the barometer file: %@", type: .error, error.localizedDescription)
            return nil
        }
        file.seekToEndOfFile()
    }

    func start() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            os_log("Barometer not available on this device.")
            return
        }
        let queue = OperationQueue()
        queue.name = "baro writer queue"
        queue.maxConcurrentOperationCount = 1
        altimeter.startRelativeAltitudeUpdates(to: queue) { [weak self] data, _ in
            guard let data = data, let self = self, self.file != nil else { return }
            let strData = String(format: self.template,
                                 timestampToInt(data.timestamp),
                                 data.pressure.doubleValue,
                                 data.relativeAltitude.doubleValue)
            if let outData = strData.data(using: .utf8) {
                self.file.write(outData)
            }
        }
    }

    func finish() {
        altimeter.stopRelativeAltitudeUpdates()
        file.closeFile()
        file = nil
    }
}

class CompassWriter {
    var file: FileHandle!
    let filename = "compass.txt"
    let header = "# timestamp, magnetic_heading, true_heading, heading_accuracy, x, y, z\n"
    let template = "%lld, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f\n"

    init?(outDir: URL) {
        let fileURL = outDir.appendingPathComponent(filename)
        if !FileManager.default.createFile(atPath: fileURL.path, contents: header.data(using: .utf8), attributes: nil) {
            os_log("Cannot create the compass file at %@", type: .error, fileURL.path)
            return nil
        }
        do {
            file = try FileHandle(forWritingTo: fileURL)
        } catch {
            os_log("Cannot create the compass file: %@", type: .error, error.localizedDescription)
            return nil
        }
        file.seekToEndOfFile()
    }

    func write(heading: CLHeading) {
        let bootDate = Date() - ProcessInfo.processInfo.systemUptime
        let strData = String(
            format: template,
            timestampToInt(heading.timestamp.timeIntervalSince(bootDate)),
            heading.magneticHeading, heading.trueHeading, heading.headingAccuracy,
            heading.x, heading.y, heading.z)
        if let outData = strData.data(using: .utf8) {
            file!.write(outData)
        } else {
            os_log("Failed to format compass string: %@", type: .fault, strData)
        }
    }

    func finish() {
        file.closeFile()
        file = nil
    }
}

class PedometerWriter {
    var file: FileHandle!
    private let pedometer = CMPedometer()
    private var recordingStart = Date()
    let filename = "pedometer.txt"
    let header = "# timestamp, steps, distance_m, avg_pace_s_m, current_pace_s_m, cadence_steps_s, floors_asc, floors_desc\n"
    let template = "%lld, %lld, %.4f, %.4f, %.4f, %.4f, %lld, %lld\n"

    init?(outDir: URL) {
        guard CMPedometer.isStepCountingAvailable() else {
            os_log("Pedometer not available on this device.")
            return nil
        }
        let fileURL = outDir.appendingPathComponent(filename)
        if !FileManager.default.createFile(atPath: fileURL.path, contents: header.data(using: .utf8), attributes: nil) {
            os_log("Cannot create the pedometer file at %@", type: .error, fileURL.path)
            return nil
        }
        do {
            file = try FileHandle(forWritingTo: fileURL)
        } catch {
            os_log("Cannot create the pedometer file: %@", type: .error, error.localizedDescription)
            return nil
        }
        file.seekToEndOfFile()
    }

    func start() {
        if #available(iOS 11.0, *) {
            let auth = CMPedometer.authorizationStatus()
            if auth == .denied || auth == .restricted {
                os_log("Pedometer: Motion & Fitness permission denied (status %d). Enable in Settings > Privacy > Motion & Fitness.", type: .error, auth.rawValue)
                return
            }
            os_log("Pedometer: authorizationStatus = %d, polling every 5s via queryPedometerData.", auth.rawValue)
        }
        recordingStart = Date()
    }

    func poll() {
        guard file != nil else { return }
        let bootDate = Date() - ProcessInfo.processInfo.systemUptime
        pedometer.queryPedometerData(from: recordingStart, to: Date()) { [weak self] data, error in
            if let error = error {
                os_log("Pedometer query error: %@", type: .error, error.localizedDescription)
                return
            }
            guard let data = data, let self = self, self.file != nil else { return }
            let strData = String(
                format: self.template,
                timestampToInt(data.endDate.timeIntervalSince(bootDate)),
                data.numberOfSteps.int64Value,
                data.distance?.doubleValue ?? 0,
                data.averageActivePace?.doubleValue ?? -1,
                data.currentPace?.doubleValue ?? -1,
                data.currentCadence?.doubleValue ?? -1,
                data.floorsAscended?.int64Value ?? 0,
                data.floorsDescended?.int64Value ?? 0)
            if let outData = strData.data(using: .utf8) {
                self.file.write(outData)
            } else {
                os_log("Failed to format pedometer string: %@", type: .fault, strData)
            }
        }
    }

    func finish() {
        file.closeFile()
        file = nil
    }
}

class WiFiWriter {
    var file: FileHandle!
    let filename = "wifi.txt"
    let header = "# timestamp, ssid, bssid\n"
    let template = "%lld, %@, %@\n"
    private var consecutiveFailures = 0
    private let maxFailures = 3
    private var disabled = false

    init?(outDir: URL) {
        let fileURL = outDir.appendingPathComponent(filename)
        if !FileManager.default.createFile(atPath: fileURL.path, contents: header.data(using: .utf8), attributes: nil) {
            os_log("Cannot create the wifi file at %@", type: .error, fileURL.path)
            return nil
        }
        do {
            file = try FileHandle(forWritingTo: fileURL)
        } catch {
            os_log("Cannot create the wifi file: %@", type: .error, error.localizedDescription)
            return nil
        }
        file.seekToEndOfFile()
    }

    func write() {
        guard !disabled else { return }
        guard let interfaces = CNCopySupportedInterfaces() as? [String], !interfaces.isEmpty else { return }
        let ts = timestampToInt(ProcessInfo.processInfo.systemUptime)
        var wrote = false
        for iface in interfaces {
            guard let info = CNCopyCurrentNetworkInfo(iface as CFString) as? [String: Any] else { continue }
            let ssid  = (info[kCNNetworkInfoKeySSID  as String] as? String ?? "").replacingOccurrences(of: ",", with: "")
            let bssid =  info[kCNNetworkInfoKeyBSSID as String] as? String ?? ""
            let strData = String(format: template, ts, ssid, bssid)
            if let outData = strData.data(using: .utf8) {
                file!.write(outData)
                wrote = true
            } else {
                os_log("Failed to format wifi string: %@", type: .fault, strData)
            }
        }
        if wrote {
            consecutiveFailures = 0
        } else {
            consecutiveFailures += 1
            if consecutiveFailures >= maxFailures {
                disabled = true
                os_log("WiFi: CNCopyCurrentNetworkInfo returned nil %d× – entitlement com.apple.developer.networking.wifi-info not configured or device not connected to WiFi. WiFi tracking disabled for this session.", type: .error, maxFailures)
            }
        }
    }

    func finish() {
        file.closeFile()
        file = nil
    }
}

// MARK: - New Streamers

class CompassStreamer {
    weak var server: StreamingServer?

    func send(heading: CLHeading) {
        server?.send(PacketBuilder.compassPacket(heading: heading))
    }
}

class PedometerStreamer {
    weak var server: StreamingServer?
    private let pedometer = CMPedometer()

    func start() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        let bootDate = Date() - ProcessInfo.processInfo.systemUptime
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let data = data, let self = self else { return }
            self.server?.send(PacketBuilder.pedometerPacket(data: data, bootDate: bootDate), dropIfBusy: true)
        }
    }

    func finish() { pedometer.stopUpdates() }
}

class WiFiStreamer {
    weak var server: StreamingServer?

    func send() {
        guard let interfaces = CNCopySupportedInterfaces() as? [String] else { return }
        for iface in interfaces {
            guard let info = CNCopyCurrentNetworkInfo(iface as CFString) as? [String: Any] else { continue }
            let ssid  = (info[kCNNetworkInfoKeySSID  as String] as? String ?? "").replacingOccurrences(of: ",", with: "")
            let bssid =  info[kCNNetworkInfoKeyBSSID as String] as? String ?? ""
            server?.send(PacketBuilder.wifiPacket(ssid: ssid, bssid: bssid))
        }
    }
}

