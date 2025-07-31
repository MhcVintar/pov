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
        let inputSize = CGSize(width: transformedSize.width, height: transformedSize.height)
        
        // Calculate output size (convert 4:3 to 16:9)
        let outputSize = CGSize(width: inputSize.height * 16/9, height: inputSize.height)
        
        // Extract additional video properties for accurate reproduction
        let originalBitrate = estimatedDataRate > 0 ? Int(estimatedDataRate) : 5_000_000 // Fallback to 5Mbps
        let originalFrameRate = nominalFrameRate > 0 ? nominalFrameRate : 30.0 // Fallback to 30fps
        
        print("Original video properties:")
        print("- Frame rate: \(originalFrameRate) fps")
        print("- Estimated bitrate: \(originalBitrate) bps")
        print("- Input size: \(inputSize)")
        print("- Output size: \(outputSize)")
        
        // Setup reader
        let reader = try AVAssetReader(asset: asset)
        
        let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])
        reader.add(videoReaderOutput)
        
        let audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
        reader.add(audioReaderOutput)
        
        // Setup writer with original video properties
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        
        // Create compression properties that match the original video
        let compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: Int(Double(originalBitrate) * 1.333333333),
            AVVideoProfileLevelKey: "HEVC_Main10_AutoLevel",
            AVVideoExpectedSourceFrameRateKey: originalFrameRate
        ]
        
        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height,
            AVVideoCompressionPropertiesKey: compressionProperties
        ])
        videoWriterInput.expectsMediaDataInRealTime = false
        
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: outputSize.width,
                kCVPixelBufferHeightKey as String: outputSize.height,
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
            
            // Process audio samples if audio track exists
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
        // Create input texture
        guard let inputTexture = createTexture(from: inputPixelBuffer) else {
            throw VideoConverterError.textureCreationFailed("Failed to create input texture")
        }
        
        // Create output pixel buffer
        var outputPixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(outputSize.width),
            Int(outputSize.height),
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferMetalCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:]
            ] as CFDictionary,
            &outputPixelBuffer
        )
        
        guard result == kCVReturnSuccess, let outputBuffer = outputPixelBuffer else {
            throw VideoConverterError.pixelBufferCreationFailed
        }
        
        // Create output texture
        guard let outputTexture = createTexture(from: outputBuffer) else {
            throw VideoConverterError.textureCreationFailed("Failed to create output texture")
        }
        
        // Execute Metal shader
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw VideoConverterError.metalExecutionFailed("Failed to create command buffer or encoder")
        }
        
        encoder.setComputePipelineState(computePipelineState)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        
        // Calculate thread groups
        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupsPerGrid = MTLSize(
            width: (outputTexture.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: (outputTexture.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
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
    
    private func createTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var texture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
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
                shaderFunctionName: "superview" // Replace with your shader function name
            )
        } catch {
            print("Failed to create converter: \(error)")
        }
    }
    
    func convertVideo(inputPath: String, outputPath: String) async {
        guard let converter = converter else {
            print("Converter not initialized")
            return
        }
        
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = URL(fileURLWithPath: outputPath)
        
        do {
            try await converter.convertVideo(
                inputURL: inputURL,
                outputURL: outputURL
            ) { progress in
                DispatchQueue.main.async {
                    print("Progress: \(Int(progress * 100))%")
                    // Update your UI progress indicator here
                }
            }
            
            print("Video conversion completed successfully!")
            
        } catch {
            print("Video conversion failed: \(error)")
        }
    }
}
