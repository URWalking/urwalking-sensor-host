//
//  StreamingServer.swift
//  ScanCapture
//
//  NWListener-based TCP server on port 12345.
//  Accepts a single client connection (USB-tunneled via iproxy on Mac),
//  parses incoming SCAP command packets, and streams sensor data packets back.
//

import Foundation
import Network
import os.log

// MARK: - Delegate

protocol StreamingServerDelegate: AnyObject {
    func serverDidReceiveStart(fps: Int?)
    func serverDidReceiveStop()
    func serverDidConnect()
    func serverDidDisconnect()
}

// MARK: - StreamingServer

class StreamingServer {

    static let port: NWEndpoint.Port = 12345

    private var listener: NWListener?
    private var connection: NWConnection?

    // Backpressure: track bytes queued in NWConnection send buffers.
    // If this exceeds the limit, dropIfBusy=true packets (IMU) are silently dropped.
    private let maxQueuedBytes = 16 * 1024 * 1024  // 16 MB
    private var queuedBytes: Int = 0
    private let queueLock = NSLock()

    weak var delegate: StreamingServerDelegate?

    // MARK: Lifecycle

    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: params, on: StreamingServer.port) else {
            os_log("StreamingServer: failed to create NWListener", type: .error)
            return
        }
        self.listener = listener

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                os_log("StreamingServer: listening on port %d", StreamingServer.port.rawValue)
            case .failed(let err):
                os_log("StreamingServer: listener failed: %@", type: .error, err.localizedDescription)
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(connection: conn)
        }

        listener.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
        connection?.cancel()
        listener = nil
        connection = nil
        resetQueuedBytes()
    }

    // MARK: Connection handling

    private func accept(connection conn: NWConnection) {
        // Cancel any existing connection — only one client at a time
        connection?.cancel()
        connection = conn
        resetQueuedBytes()

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                os_log("StreamingServer: client connected")
                self?.delegate?.serverDidConnect()
                self?.receiveHeader(on: conn)
            case .failed(let err):
                os_log("StreamingServer: connection failed: %@", err.localizedDescription)
                self?.delegate?.serverDidDisconnect()
            case .cancelled:
                os_log("StreamingServer: connection cancelled")
                self?.delegate?.serverDidDisconnect()
            default:
                break
            }
        }

        conn.start(queue: .global(qos: .userInitiated))
    }

    // MARK: Receive command loop

    /// Read exactly 14 bytes (one SCAP packet header).
    private func receiveHeader(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 14, maximumLength: 14) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                os_log("StreamingServer: receive error: %@", error.localizedDescription)
                self.delegate?.serverDidDisconnect()
                return
            }
            guard let data = data, data.count == 14 else {
                if isComplete { self.delegate?.serverDidDisconnect() }
                return
            }

            // Validate magic "SCAP"
            guard data[0] == 0x53, data[1] == 0x43, data[2] == 0x41, data[3] == 0x50 else {
                os_log("StreamingServer: bad magic, dropping and re-syncing")
                self.receiveHeader(on: conn)
                return
            }

            let pktType = data[4]
            // Read payload length (bytes 10–13, little-endian) byte-by-byte to avoid
            // misaligned pointer crash — Data slices have no alignment guarantees.
            let payloadLen = UInt32(data[10])
                | (UInt32(data[11]) << 8)
                | (UInt32(data[12]) << 16)
                | (UInt32(data[13]) << 24)

            self.receivePayload(on: conn, type: pktType, length: Int(payloadLen))
        }
    }

    private func receivePayload(on conn: NWConnection, type: UInt8, length: Int) {
        let handle: (Data?) -> Void = { [weak self] payload in
            guard let self = self else { return }
            switch type {
            case 0x01:  // CMD_START
                os_log("StreamingServer: received START")
                var requestedFps: Int? = nil
                if let data = payload, data.count >= 2 {
                    let raw = UInt16(data[0]) | (UInt16(data[1]) << 8)
                    if raw >= 1 && raw <= 60 { requestedFps = Int(raw) }
                }
                self.send(PacketBuilder.ackPacket(ok: true))
                DispatchQueue.main.async { self.delegate?.serverDidReceiveStart(fps: requestedFps) }
            case 0x02:  // CMD_STOP
                os_log("StreamingServer: received STOP")
                self.send(PacketBuilder.ackPacket(ok: true))
                DispatchQueue.main.async { self.delegate?.serverDidReceiveStop() }
            case 0x03:  // CMD_PING
                self.send(PacketBuilder.ackPacket(ok: true))
            default:
                os_log("StreamingServer: unknown command type 0x%02x", type)
            }
            self.receiveHeader(on: conn)
        }

        if length > 0 {
            conn.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, _ in
                handle(data)
            }
        } else {
            handle(nil)
        }
    }

    // MARK: Send

    /// Send a data packet. If dropIfBusy=true, the packet is silently dropped when
    /// the send buffer is full (useful for high-frequency IMU streams).
    func send(_ data: Data, dropIfBusy: Bool = false) {
        guard let conn = connection else { return }

        queueLock.lock()
        if dropIfBusy && queuedBytes > maxQueuedBytes {
            queueLock.unlock()
            return
        }
        queuedBytes += data.count
        queueLock.unlock()

        conn.send(content: data, completion: .contentProcessed({ [weak self] _ in
            self?.queueLock.lock()
            self?.queuedBytes -= data.count
            self?.queueLock.unlock()
        }))
    }

    // MARK: Helpers

    private func resetQueuedBytes() {
        queueLock.lock()
        queuedBytes = 0
        queueLock.unlock()
    }
}
