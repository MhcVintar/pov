import AVFoundation
import MetalKit

class VideoService {
    private let metalDevice: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureCache: CVMetalTextureCache
    private let textureSampler: MTLSamplerState
    private let horizontalPipelineState: MTLComputePipelineState
    private let verticalPipelineState: MTLComputePipelineState
    private let downscalePipelineState: MTLComputePipelineState
    private let cropPipelineState: MTLComputePipelineState

    init() throws {
        // Create metal device
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            throw AppError.fatalError("Failed to create a metal device.")
        }
        self.metalDevice = metalDevice
        
        // Create command queue
        guard let commandQueue = metalDevice.makeCommandQueue() else {
            throw AppError.fatalError("Failed to create command queue.")
        }
        self.commandQueue = commandQueue
        
        // Create texture cache
        var textureCache: CVMetalTextureCache?
        let result = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &textureCache)
        guard result == kCVReturnSuccess, let textureCache = textureCache else {
            throw AppError.fatalError("Failed to create a texture cache.")
        }
        self.textureCache = textureCache
        
        // Create texture sampler
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.normalizedCoordinates = true
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        
        guard let textureSampler = metalDevice.makeSamplerState(descriptor: samplerDescriptor) else {
            throw AppError.fatalError("Failed to create a texture sampler.")
        }
        self.textureSampler = textureSampler
        
        // Create pipeline states
        guard let metalLibrary = metalDevice.makeDefaultLibrary() else {
            throw AppError.fatalError("Failed to create metal library.")
        }
        
        horizontalPipelineState = try Self.getPipelineState(
            metalDevice: metalDevice,
            metalLibrary: metalLibrary,
            functionName: "horizontal"
        )
        verticalPipelineState = try Self.getPipelineState(
            metalDevice: metalDevice,
            metalLibrary: metalLibrary,
            functionName: "vertical"
        )
        downscalePipelineState = try Self.getPipelineState(
            metalDevice: metalDevice,
            metalLibrary: metalLibrary,
            functionName: "downscale"
        )
        cropPipelineState = try Self.getPipelineState(
            metalDevice: metalDevice,
            metalLibrary: metalLibrary,
            functionName: "crop"
        )
    }
    
    private static func getPipelineState(
        metalDevice: MTLDevice,
        metalLibrary: MTLLibrary,
        functionName: String
    ) throws -> MTLComputePipelineState {
        guard let metalFunction = metalLibrary.makeFunction(name: functionName) else {
            throw AppError.fatalError("Failed to find \(functionName) shader function.")
        }
        
        return try metalDevice.makeComputePipelineState(function: metalFunction)
    }
    
    func processVideo(
        inputAsset: AVAsset,
        outputURL: URL,
        orientation: Orientation,
        quality: Quality,
        progressCallback: @escaping (Double) -> Void
    ) async throws {
        // Load video and audio tracks
        let (
            videoTrack,
            audioTrack
        ) = try await (
            inputAsset.loadTracks(withMediaType: .video).first,
            inputAsset.loadTracks(withMediaType: .audio).first
        )
        
        guard let videoTrack else {
            throw AppError.recoverableError("Failed to load video track.")
        }
        guard let audioTrack else {
            throw AppError.recoverableError("Failed to load audio track.")
        }
        
        // Prepare metadata
        let metadata = try await Utils.getMetadata(from: inputAsset)
        
        let totalFrames = metadata.duration.seconds * metadata.frameRate
        
        let outputSize: CGSize = switch orientation {
        case .horizontal:
            quality.size16by9
        case .vertical:
            quality.size9by16
        }
        
        let outputBitRate = metadata.bitRate * (outputSize.width * outputSize.height) / (metadata.resolution.width * metadata.resolution.height)
        
        // Setup reader
        let reader = try AVAssetReader(asset: inputAsset)
        
        let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])
        reader.add(videoReaderOutput)
        
        let audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
        reader.add(audioReaderOutput)
        
        // Setup writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        
        if let creationDate = try await inputAsset.load(.creationDate) {
            writer.metadata.append(creationDate)
        }
        
        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: outputBitRate,
                AVVideoProfileLevelKey: "HEVC_Main10_AutoLevel",
                // TODO: should we make this an int instead of a double
                AVVideoExpectedSourceFrameRateKey: metadata.frameRate,
            ]
        ])
        videoWriterInput.expectsMediaDataInRealTime = false
        writer.add(videoWriterInput)
        
        let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        writer.add(audioWriterInput)
        
        // Setup pixel buffer adaptor
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height),
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )
        
        // Setup pixel buffer pools
        let pixelBufferPools = try getPixelBufferPools(orientation: orientation, quality: quality)
        
        // Start reading and writing
        guard reader.startReading() else {
            throw AppError.recoverableError(reader.error?.localizedDescription ?? "Unknown reader error.")
        }
        
        guard writer.startWriting() else {
            throw AppError.recoverableError(writer.error?.localizedDescription ?? "Unknown writer error.")
        }
        writer.startSession(atSourceTime: .zero)

        // Process the frames
        var processedFrames = 0
        var lastProgress = 0.0
        while reader.status == .reading && !Task.isCancelled {
            var shouldWait = true
            
            // Process video
            if videoWriterInput.isReadyForMoreMediaData {
                shouldWait = false
                
                if let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() {
                    guard let inputPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                        throw AppError.recoverableError("Failed to convert sample buffer to image buffer.")
                    }
                    
                    let outputPixelBuffer = switch orientation {
                    case .horizontal:
                        try await self.processHorizontalFrame(
                            inputPixelBuffer: inputPixelBuffer,
                            pixelBufferPools: pixelBufferPools,
                            quality: quality
                        )
                    case .vertical:
                        try await self.processVerticalFrame(
                            inputPixelBuffer: inputPixelBuffer,
                            pixelBufferPools: pixelBufferPools,
                            quality: quality
                        )
                    }
                    
                    
                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    if !pixelBufferAdaptor.append(outputPixelBuffer, withPresentationTime: presentationTime) {
                        throw AppError.recoverableError("Failed to append pixel buffer at time: \(presentationTime).")
                    }
                    
                    processedFrames += 1
                    let progress = Double(processedFrames) / Double(totalFrames)
                    if progress - lastProgress >= 0.01 || progress >= 1 {
                        lastProgress = progress
                        await MainActor.run {
                            progressCallback(min(progress, 1.0))
                        }
                    }
                } else {
                    videoWriterInput.markAsFinished()
                }
            }

            // Process audio
            if audioWriterInput.isReadyForMoreMediaData {
                shouldWait = false
                
                if let sampleBuffer = audioReaderOutput.copyNextSampleBuffer() {
                    if !audioWriterInput.append(sampleBuffer) {
                        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        throw AppError.recoverableError("Failed to append audio sample at time: \(presentationTime).")
                    }
                } else {
                    audioWriterInput.markAsFinished()
                }
            }
            
            if shouldWait {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        
        // Handle cancellation
        if Task.isCancelled {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            return
        }
        
        // Finish writing
        await writer.finishWriting()
        
        if let error = reader.error {
            throw AppError.recoverableError(error.localizedDescription)
        }
        
        if let error = writer.error {
            throw AppError.recoverableError(error.localizedDescription)
        }
    }
    
    private func getPixelBufferPools(
        orientation: Orientation,
        quality: Quality
    ) throws -> [CGSize: CVPixelBufferPool] {
        let sizes = switch orientation {
        case .horizontal:
            [
                CGSize(
                    width: quality.size16by9.height / 3 * 4,
                    height: quality.size16by9.height
                ),
                quality.size16by9
            ]
        case .vertical:
            [
                CGSize(
                    width: quality.size4by3.width,
                    height: quality.size4by3.height
                ),
                CGSize(
                    width: quality.size4by3.height / 8 * 5,
                    height: quality.size4by3.height
                ),
                quality.size9by16
            ]
        }
        
        var pools: [CGSize: CVPixelBufferPool] = [:]
        
        for size in sizes {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            
            var pool: CVPixelBufferPool?
            let result = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
            
            guard result == kCVReturnSuccess, let pool = pool else {
                throw AppError.recoverableError("Failed to create pixel buffer pool.")
            }
            pools[size] = pool
        }
        
        return pools
    }
    
    private func processHorizontalFrame(
        inputPixelBuffer: CVPixelBuffer,
        pixelBufferPools: [CGSize: CVPixelBufferPool],
        quality: Quality
    ) async throws -> CVPixelBuffer {
        let intermediateSize = CGSize(
            width: quality.size16by9.height / 3 * 4,
            height: quality.size16by9.height
        )
        guard let pixelBufferPool = pixelBufferPools[intermediateSize] else {
            throw AppError.recoverableError("Failed to get pixel buffer pool.")
        }
        let intermeidatePixelBuffer = try await processFrameWithShader(
            inputPixelBuffer: inputPixelBuffer,
            pixelBufferPool: pixelBufferPool,
            pipelineState: downscalePipelineState,
            useSampler: true
        )
        
        guard let pixelBufferPool = pixelBufferPools[quality.size16by9] else {
            throw AppError.recoverableError("Failed to get pixel buffer pool.")
        }
        return try await processFrameWithShader(
            inputPixelBuffer: intermeidatePixelBuffer,
            pixelBufferPool: pixelBufferPool,
            pipelineState: horizontalPipelineState,
        )
    }
    
    private func processVerticalFrame(
        inputPixelBuffer: CVPixelBuffer,
        pixelBufferPools: [CGSize: CVPixelBufferPool],
        quality: Quality
    ) async throws -> CVPixelBuffer {
        var intermediateSize = CGSize(
            width: quality.size4by3.width,
            height: quality.size4by3.height
        )
        guard let pixelBufferPool = pixelBufferPools[intermediateSize] else {
            throw AppError.recoverableError("Failed to get pixel buffer pool.")
        }
        var intermeidatePixelBuffer = try await processFrameWithShader(
            inputPixelBuffer: inputPixelBuffer,
            pixelBufferPool: pixelBufferPool,
            pipelineState: downscalePipelineState,
            useSampler: true
        )

        intermediateSize = CGSize(
            width: quality.size4by3.height / 8 * 5,
            height: quality.size4by3.height
        )
        guard let pixelBufferPool = pixelBufferPools[intermediateSize] else {
            throw AppError.recoverableError("Failed to get pixel buffer pool.")
        }
        intermeidatePixelBuffer = try await processFrameWithShader(
            inputPixelBuffer: intermeidatePixelBuffer,
            pixelBufferPool: pixelBufferPool,
            pipelineState: cropPipelineState,
        )

        guard let pixelBufferPool = pixelBufferPools[quality.size9by16] else {
            throw AppError.recoverableError("Failed to get pixel buffer pool.")
        }
        return try await processFrameWithShader(
            inputPixelBuffer: intermeidatePixelBuffer,
            pixelBufferPool: pixelBufferPool,
            pipelineState: verticalPipelineState,
        )
    }

    private func processFrameWithShader(
        inputPixelBuffer: CVPixelBuffer,
        pixelBufferPool: CVPixelBufferPool,
        pipelineState: MTLComputePipelineState,
        useSampler: Bool = false
    ) async throws -> CVPixelBuffer {
        // Create input textures
        guard let inputYTexture = createTexture(from: inputPixelBuffer, plain: .y),
              let inputUVTexture = createTexture(from: inputPixelBuffer, plain: .uv) else {
            throw AppError.recoverableError("Failed to create textures from the input pixel buffer.")
        }
        
        // Create output pixel buffer
        var outputPixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &outputPixelBuffer)
        
        guard result == kCVReturnSuccess, let outputBuffer = outputPixelBuffer else {
            throw AppError.recoverableError("Failed to create output pixel buffer.")
        }
        
        // Create output textures
        guard let outputYTexture = createTexture(from: outputBuffer, plain: .y),
              let outputUVTexture = createTexture(from: outputBuffer, plain: .uv) else {
            throw AppError.recoverableError("Failed to create textures from the output pixel buffer.")
        }
        
        // Setup encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw AppError.recoverableError("Failed to create command buffer or encoder.")
        }
        
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(inputYTexture, index: 0)
        encoder.setTexture(inputUVTexture, index: 1)
        encoder.setTexture(outputYTexture, index: 2)
        encoder.setTexture(outputUVTexture, index: 3)
        if useSampler {
            encoder.setSamplerState(textureSampler, index: 0)
        }
        
        // Calculate thread groups based on output Y texture size
        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupsPerGrid = MTLSize(
            width: (outputYTexture.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: (outputYTexture.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )
        
        // Process the frame
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        await commandBuffer.completed()
        
        if let error = commandBuffer.error {
            throw AppError.recoverableError(error.localizedDescription)
        }
        
        return outputBuffer
    }
    
    private func createTexture(from pixelBuffer: CVPixelBuffer, plain: TexturePlain) -> MTLTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, plain.index)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, plain.index)
        
        var texture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            plain.pixelFormat,
            width,
            height,
            plain.index,
            &texture
        )
        
        guard result == kCVReturnSuccess, let cvTexture = texture else {
            return nil
        }
        
        return CVMetalTextureGetTexture(cvTexture)
    }
}

enum TexturePlain {
    case y
    case uv
    
    var index: Int {
        return switch self {
        case .y: 0
        case .uv: 1
        }
    }
    
    var pixelFormat: MTLPixelFormat {
        return switch self {
        case .y: .r16Unorm
        case .uv: .rg16Unorm
        }
    }
}
