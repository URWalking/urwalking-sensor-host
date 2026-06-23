//
//  VideoEncoder.swift
//  ScanCapture
//
//  H.264 encoder using VideoToolbox VTCompressionSession.
//  Delivers compressed NAL data (AVCC format) to a callback without writing to disk.
//

import Foundation
import VideoToolbox
import CoreVideo
import CoreMedia
import os.log

class VideoEncoder {

    // Called on a background thread when each frame is encoded.
    // Parameters: (nalData in AVCC format, isKeyframe, presentationTimestamp)
    var onEncodedFrame: ((Data, Bool, CMTime) -> Void)?

    private var session: VTCompressionSession?
    private(set) var width: Int = 0
    private(set) var height: Int = 0
    private var frameIndex: Int64 = 0
    // Force a keyframe every N encoded frames (~2 seconds at 10 fps)
    private let keyframeInterval: Int64 = 20

    // MARK: Setup

    func setup(width: Int, height: Int) {
        guard session == nil else { return }
        self.width = width
        self.height = height

        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: encodedFrameCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )

        guard status == noErr, let session = session else {
            os_log("VideoEncoder: VTCompressionSessionCreate failed: %d", type: .error, status)
            return
        }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: kVTProfileLevel_H264_High_AutoLevel)
        // ~2 Mbps target — sufficient for ARKit resolution at 10 fps
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: 2_000_000 as CFNumber)

        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(session)
        if prepareStatus != noErr {
            os_log("VideoEncoder: prepare failed: %d", type: .error, prepareStatus)
        }
    }

    // MARK: Encode

    func encode(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let session = session else { return }

        let forceKeyframe = (frameIndex % keyframeInterval == 0)
        let frameProperties: CFDictionary? = forceKeyframe
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
            : nil

        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: timestamp,
            duration: .invalid,
            frameProperties: frameProperties,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
        frameIndex += 1
    }

    // MARK: Teardown

    func finish() {
        guard let session = session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
        self.session = nil
        frameIndex = 0
    }

    // MARK: Encoded-frame callback (C function)

    private let encodedFrameCallback: VTCompressionOutputCallback = { refCon, _, status, _, sampleBuffer in
        guard let refCon = refCon else { return }
        let encoder = Unmanaged<VideoEncoder>.fromOpaque(refCon).takeUnretainedValue()
        encoder.handleEncodedFrame(status: status, sampleBuffer: sampleBuffer)
    }

    private func handleEncodedFrame(status: OSStatus, sampleBuffer: CMSampleBuffer?) {
        guard status == noErr, let sb = sampleBuffer else {
            if status != noErr {
                os_log("VideoEncoder: encode error: %d", type: .error, status)
            }
            return
        }

        // Determine if this is a keyframe (IDR)
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[CFString: Any]]
        let isNotSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        let isKeyframe = !isNotSync

        let pts = CMSampleBufferGetPresentationTimeStamp(sb)

        // Build NAL data in AVCC format
        var nalData = Data()

        // Prepend SPS and PPS parameter sets for keyframes so the receiver can initialize a decoder
        if isKeyframe, let formatDesc = CMSampleBufferGetFormatDescription(sb) {
            nalData.append(extractParameterSets(from: formatDesc))
        }

        // Append the encoded frame data from CMBlockBuffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sb) else { return }
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>? = nil
        let copyStatus = CMBlockBufferGetDataPointer(
            blockBuffer, atOffset: 0,
            lengthAtOffsetOut: nil, totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer)
        guard copyStatus == kCMBlockBufferNoErr, let ptr = dataPointer else { return }
        nalData.append(Data(bytes: ptr, count: totalLength))

        onEncodedFrame?(nalData, isKeyframe, pts)
    }

    /// Extract SPS and PPS NAL units from a H.264 format description, in AVCC format
    /// (4-byte big-endian length prefix before each NAL unit).
    private func extractParameterSets(from desc: CMFormatDescription) -> Data {
        var data = Data()
        var paramSetCount = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            desc, parameterSetIndex: 0,
            parameterSetPointerOut: nil, parameterSetSizeOut: nil,
            parameterSetCountOut: &paramSetCount, nalUnitHeaderLengthOut: nil)

        for i in 0..<paramSetCount {
            var paramSetPtr: UnsafePointer<UInt8>? = nil
            var paramSetSize: Int = 0
            let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                desc, parameterSetIndex: i,
                parameterSetPointerOut: &paramSetPtr, parameterSetSizeOut: &paramSetSize,
                parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
            if status == noErr, let ptr = paramSetPtr {
                // Write 4-byte big-endian length (AVCC format)
                var len = UInt32(paramSetSize).bigEndian
                withUnsafeBytes(of: &len) { data.append(contentsOf: $0) }
                data.append(Data(bytes: ptr, count: paramSetSize))
            }
        }
        return data
    }
}
