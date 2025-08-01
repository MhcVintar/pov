//
//  VideoProcessor.swift
//  POV
//
//  Created by Miha Vintar on 31. 7. 25.
//

//
//  VideoProcessor.swift
//  POV
//
//  Created by Miha Vintar on 31. 7. 25.
//

import AVFoundation
import Metal
import MetalKit
import CoreVideo

class VideoAspectRatioConverter {
    private let metalDevice: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let computePipelineState: MTLComputePipelineState
    private let textureCache: CVMetalTextureCache
    
    init(metalDevice: MTLDevice, shaderFunctionName: String = "superview") throws {
        self.metalDevice = metalDevice
        
        guard let commandQueue = metalDevice.makeCommandQueue() else {
            throw VideoConverterError.metalSetupFailed("Failed to create command queue")
        }
        self.commandQueue = commandQueue
        
        // Create texture cache
        var textureCache: CVMetalTextureCache?
        let result = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &textureCache)
        guard result == kCVReturnSuccess, let cache = textureCache else {
            throw VideoConverterError.metalSetupFailed("Failed to create texture cache")
        }
        self.textureCache = cache
        
        // Load and compile shader
        guard let defaultLibrary = metalDevice.makeDefaultLibrary() else {
            throw VideoConverterError.metalSetupFailed("Failed to create default library")
        }
        
        guard let function = defaultLibrary.makeFunction(name: shaderFunctionName) else {
            throw VideoConverterError.metalSetupFailed("Failed to find shader function: \(shaderFunctionName)")
        }
        
        do {
            self.computePipelineState = try metalDevice.makeComputePipelineState(function: function)
        } catch {
            throw VideoConverterError.metalSetupFailed("Failed to create compute pipeline state: \(error)")
        }
    }
    
    func convertVideo(inputURL: URL, outputURL: URL, progressCallback: @escaping (Float) -> Void) async throws {
        let asset = AVURLAsset(url: inputURL)
        
        // Get video track
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoConverterError.noVideoTrack
        }
        
        // Get audio track
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw VideoConverterError.noAudioTrack
        }
        
        // Load original video properties
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let estimatedDataRate = try await videoTrack.load(.estimatedDataRate)
        
        // Calculate actual dimensions considering transform
        let transformedSize = naturalSize.applying(transform)
        let inputSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        
        // Calculate output size (convert 4:3 to 16:9)
        let outputSize = CGSize(width: inputSize.height * 16/9, height: inputSize.height)
        
        // Extract additional video properties for accurate reproduction
        let originalBitrate = estimatedDataRate > 0 ? Int(estimatedDataRate) : 8_000_000 // Higher fallback for 10-bit
        let originalFrameRate = nominalFrameRate > 0 ? nominalFrameRate : 30.0
        
        // Calculate bitrate accounting for resolution increase and 10-bit content
        let resolutionRatio = (outputSize.width * outputSize.height) / (inputSize.width * inputSize.height)
        let targetBitrate = Int(Double(originalBitrate) * resolutionRatio * 1.15) // 15% overhead for new content
        
        print("Original video properties:")
        print("- Frame rate: \(originalFrameRate) fps")
        print("- Estimated bitrate: \(originalBitrate) bps")
        print("- Target bitrate: \(targetBitrate) bps")
        print("- Input size: \(inputSize)")
        print("- Output size: \(outputSize)")
        
        // Setup reader with YUV420 10-bit format preservation
        let reader = try AVAssetReader(asset: asset)
        
        let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])
        reader.add(videoReaderOutput)
        
        let audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
        reader.add(audioReaderOutput)
        
        // Setup writer with 10-bit HEVC encoding
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        
        // Create compression properties optimized for 10-bit content
        let compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: targetBitrate,
            AVVideoProfileLevelKey: "HEVC_Main10_AutoLevel",
            AVVideoExpectedSourceFrameRateKey: originalFrameRate,
        ]
        
        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: compressionProperties
        ])
        videoWriterInput.expectsMediaDataInRealTime = false
        
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height),
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )
        
        writer.add(videoWriterInput)
        
        let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        writer.add(audioWriterInput)
        
        // Start reading and writing
        guard reader.startReading() else {
            throw VideoConverterError.readerFailed(reader.error?.localizedDescription ?? "Unknown error")
        }
        
        guard writer.startWriting() else {
            throw VideoConverterError.writerFailed(writer.error?.localizedDescription ?? "Unknown error")
        }
        
        writer.startSession(atSourceTime: .zero)
        
        // Calculate total frames more accurately using actual frame rate and duration
        let duration = try await asset.load(.duration)
        let totalFrames = Int(duration.seconds * Double(originalFrameRate))
        var processedFrames = 0
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            
            // Process video frames
            group.addTask {
                while reader.status == .reading {
                    if videoWriterInput.isReadyForMoreMediaData {
                        guard let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() else {
                            break
                        }
                        
                        guard let inputPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                            continue
                        }
                        
                        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        
                        let outputPixelBuffer = try await self.processFrame(
                            inputPixelBuffer: inputPixelBuffer,
                            outputSize: outputSize
                        )
                        
                        if !pixelBufferAdaptor.append(outputPixelBuffer, withPresentationTime: presentationTime) {
                            print("Failed to append pixel buffer at time: \(presentationTime)")
                        }
                        
                        processedFrames += 1
                        let progress = Float(processedFrames) / Float(totalFrames)
                        await MainActor.run {
                            progressCallback(min(progress, 1.0))
                        }
                        
                    } else {
                        // Wait a bit if writer isn't ready
                        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    }
                }
                
                videoWriterInput.markAsFinished()
            }
            
            // Process audio samples
            group.addTask {
                while reader.status == .reading {
                    if audioWriterInput.isReadyForMoreMediaData {
                        guard let sampleBuffer = audioReaderOutput.copyNextSampleBuffer() else {
                            break
                        }
                        
                        if !audioWriterInput.append(sampleBuffer) {
                            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                            print("Failed to append audio sample at time: \(presentationTime)")
                        }
                        
                    } else {
                        // Wait a bit if writer isn't ready
                        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    }
                }
                
                audioWriterInput.markAsFinished()
            }
            
            // Wait for all tasks to complete
            try await group.waitForAll()
        }
        
        // Finish writing
        await writer.finishWriting()
        
        if let error = writer.error {
            throw VideoConverterError.writerFailed(error.localizedDescription)
        }
        
        if let error = reader.error {
            throw VideoConverterError.readerFailed(error.localizedDescription)
        }
    }
    
    private func processFrame(inputPixelBuffer: CVPixelBuffer, outputSize: CGSize) async throws -> CVPixelBuffer {
        // Create input textures for YUV420 10-bit (bi-planar)
        guard let yTexture = createYTexture(from: inputPixelBuffer),
              let uvTexture = createUVTexture(from: inputPixelBuffer) else {
            throw VideoConverterError.textureCreationFailed("Failed to create input YUV textures")
        }
        
        // Create output pixel buffer in YUV420 10-bit format
        var outputPixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(outputSize.width),
            Int(outputSize.height),
            kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            [
                kCVPixelBufferMetalCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:]
            ] as CFDictionary,
            &outputPixelBuffer
        )
        
        guard result == kCVReturnSuccess, let outputBuffer = outputPixelBuffer else {
            throw VideoConverterError.pixelBufferCreationFailed
        }
        
        // Create output textures
        guard let outputYTexture = createYTexture(from: outputBuffer),
              let outputUVTexture = createUVTexture(from: outputBuffer) else {
            throw VideoConverterError.textureCreationFailed("Failed to create output YUV textures")
        }
        
        // Execute Metal shader
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw VideoConverterError.metalExecutionFailed("Failed to create command buffer or encoder")
        }
        
        encoder.setComputePipelineState(computePipelineState)
        encoder.setTexture(yTexture, index: 0)      // Input Y plane
        encoder.setTexture(uvTexture, index: 1)     // Input UV plane
        encoder.setTexture(outputYTexture, index: 2) // Output Y plane
        encoder.setTexture(outputUVTexture, index: 3) // Output UV plane
        
        // Calculate thread groups based on output Y texture size
        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupsPerGrid = MTLSize(
            width: (outputYTexture.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: (outputYTexture.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        if let error = commandBuffer.error {
            throw VideoConverterError.metalExecutionFailed(error.localizedDescription)
        }
        
        return outputBuffer
    }
    
    private func createYTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        
        var texture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .r16Unorm, // 10-bit Y plane uses 16-bit format
            width,
            height,
            0, // Y plane index
            &texture
        )
        
        guard result == kCVReturnSuccess, let cvTexture = texture else {
            return nil
        }
        
        return CVMetalTextureGetTexture(cvTexture)
    }
    
    private func createUVTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        
        var texture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .rg16Unorm, // 10-bit UV plane uses 16-bit format
            width,
            height,
            1, // UV plane index
            &texture
        )
        
        guard result == kCVReturnSuccess, let cvTexture = texture else {
            return nil
        }
        
        return CVMetalTextureGetTexture(cvTexture)
    }
}

enum VideoConverterError: Error, LocalizedError {
    case metalSetupFailed(String)
    case noVideoTrack
    case noAudioTrack
    case readerFailed(String)
    case writerFailed(String)
    case textureCreationFailed(String)
    case pixelBufferCreationFailed
    case metalExecutionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .metalSetupFailed(let message):
            return "Metal setup failed: \(message)"
        case .noVideoTrack:
            return "No video track found in input file"
        case .noAudioTrack:
            return "No audio track found in input file"
        case .readerFailed(let message):
            return "Video reader failed: \(message)"
        case .writerFailed(let message):
            return "Video writer failed: \(message)"
        case .textureCreationFailed(let message):
            return "Texture creation failed: \(message)"
        case .pixelBufferCreationFailed:
            return "Failed to create output pixel buffer"
        case .metalExecutionFailed(let message):
            return "Metal execution failed: \(message)"
        }
    }
}

class VideoConverterViewController {
    private var converter: VideoAspectRatioConverter?
    
    func setupConverter() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }
        
        do {
            converter = try VideoAspectRatioConverter(
                metalDevice: device,
                shaderFunctionName: "superview" // Use "superview_yuv_hq" for higher quality
            )
        } catch {
            print("Failed to create converter: \(error)")
        }
    }
    
    func convertVideo(inputPath: String, outputPath: String, progressCallback: @escaping (Float) -> Void) async throws {
        guard let converter = converter else {
            throw VideoConverterError.metalSetupFailed("Converter not initialized")
        }
        
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = URL(fileURLWithPath: outputPath)
        
        try await converter.convertVideo(
            inputURL: inputURL,
            outputURL: outputURL,
            progressCallback: progressCallback
        )
        
        print("Video conversion completed successfully!")
    }
}
