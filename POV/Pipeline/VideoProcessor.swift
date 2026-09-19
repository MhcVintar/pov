import AVFoundation
import CoreImage

class VideoProcessor {
    // Forces point sampling in the warp kernels below, matching the original
    // shader's exact pixel copies instead of Core Image's default interpolation.
    private static let nearestSamplerFilterKey = "CISamplerFilterMode"
    private static let nearestSamplerFilterValue = "CISamplerFilterNearest"

    // Shown to the user for any processing failure below — the specific AVFoundation/
    // Core Image failure reason isn't actionable for them, so we keep one plain message
    // rather than surfacing framework-internal text.
    private static let processingFailureMessage = "Something went wrong while processing your video. Please try again."

    // Shared by the reader output and the writer's pixel buffer adaptor so
    // both ends of the pipeline agree on the pixel format.
    private static let pixelBufferAttributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        kCVPixelBufferMetalCompatibilityKey as String: true
    ]

    private let context: CIContext
    private let horizontalWarpKernel: CIKernel
    private let verticalWarpKernel: CIKernel

    // TODO: uses the deprecated CIKernel Language (string) API — switch to a Metal-based CIKernel (with a nearest-filtering sampler) once Apple's toolchain bug with .ci.metal kernels (function not found at runtime, see project memory) is fixed.
    private static let horizontalWarpSource = """
    kernel vec4 horizontalWarp(sampler source, float inWidth, float outWidth)
    {
        vec2 outCoord = destCoord();
        float normalizedOutX = (outCoord.x / outWidth - 0.5) * 2.0;
        float inX = outCoord.x - (outWidth - inWidth) / 2.0;
        float offset = pow(normalizedOutX, 2.0) * sign(normalizedOutX) * ((outWidth - inWidth) / 2.0);
        vec2 inCoord = vec2(inX - offset, outCoord.y);
        return sample(source, samplerTransform(source, inCoord));
    }
    """

    // TODO: uses the deprecated CIKernel Language (string) API — switch to a Metal-based CIKernel (with a nearest-filtering sampler) once Apple's toolchain bug with .ci.metal kernels (function not found at runtime, see project memory) is fixed.
    private static let verticalWarpSource = """
    kernel vec4 verticalWarp(sampler source, float inWidth, float inHeight, float outWidth, float outHeight)
    {
        vec2 outCoord = destCoord();

        float normalizedOutX = (outCoord.x / outWidth - 0.5) * 2.0;
        float inX = outCoord.x - (outWidth - inWidth) / 2.0;
        float offsetX = pow(normalizedOutX, 2.0) * sign(normalizedOutX) * ((inWidth - outWidth) / 2.0);

        float normalizedOutY = (outCoord.y / outHeight - 0.5) * 2.0;
        float inY = outCoord.y - (outHeight - inHeight) / 2.0;
        float offsetY = pow(normalizedOutY, 2.0) * sign(normalizedOutY) * ((outHeight - inHeight) / 2.0);

        vec2 inCoord = vec2(inX + offsetX, inY - offsetY);
        return sample(source, samplerTransform(source, inCoord));
    }
    """

    init() throws {
        context = CIContext()

        guard let horizontalWarpKernel = CIKernel(source: Self.horizontalWarpSource) else {
            throw AppError.fatalError
        }
        self.horizontalWarpKernel = horizontalWarpKernel

        guard let verticalWarpKernel = CIKernel(source: Self.verticalWarpSource) else {
            throw AppError.fatalError
        }
        self.verticalWarpKernel = verticalWarpKernel
    }

    func processVideo(
        inputAsset: AVAsset,
        outputURL: URL,
        orientation: Orientation,
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
            throw AppError.recoverableError(Self.processingFailureMessage)
        }
        guard let audioTrack else {
            throw AppError.recoverableError(Self.processingFailureMessage)
        }

        // Prepare metadata
        let metadata = try await Self.getMetadata(from: inputAsset)

        let totalFrames = metadata.duration.seconds * metadata.frameRate

        // The horizontal warp kernel's shape is tuned against a 16:9 canvas at the
        // input's native height, but the output width must match the input's own
        // width rather than growing/shrinking to fit that canvas — horizontalWarpWidth
        // carries that 16:9-at-native-height width down to processHorizontalFrame so
        // it can pre-scale the input by the same ratio before warping, keeping the
        // warp's shape while landing back on the input's width.
        let horizontalWarpWidth = Self.evenSize(height: metadata.resolution.height, aspectWidth: 16, aspectHeight: 9).width

        let outputSize: CGSize = switch orientation {
        case .horizontal:
            // Full input width, height cropped down to 16:9.
            Self.evenSize(width: metadata.resolution.width, aspectWidth: 16, aspectHeight: 9)
        case .vertical:
            Self.evenSize(height: metadata.resolution.height, aspectWidth: 9, aspectHeight: 16)
        }

        let outputBitRate = metadata.bitRate * (outputSize.width * outputSize.height) / (metadata.resolution.width * metadata.resolution.height)

        // Setup reader
        let reader = try AVAssetReader(asset: inputAsset)

        let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: Self.pixelBufferAttributes)
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
                AVVideoExpectedSourceFrameRateKey: metadata.frameRate,
            ]
        ])
        videoWriterInput.expectsMediaDataInRealTime = false
        writer.add(videoWriterInput)

        let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        writer.add(audioWriterInput)

        // Setup pixel buffer adaptor
        // Width/height aren't specified here: the adaptor derives them from
        // videoWriterInput's own outputSettings (AVVideoWidthKey/HeightKey) above.
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput,
            sourcePixelBufferAttributes: Self.pixelBufferAttributes
        )

        // Start reading and writing
        guard reader.startReading() else {
            throw AppError.recoverableError(Self.processingFailureMessage)
        }

        guard writer.startWriting() else {
            throw AppError.recoverableError(Self.processingFailureMessage)
        }
        writer.startSession(atSourceTime: .zero)

        guard let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool else {
            throw AppError.recoverableError(Self.processingFailureMessage)
        }

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
                        throw AppError.recoverableError(Self.processingFailureMessage)
                    }

                    let outputPixelBuffer = try processFrame(
                        inputPixelBuffer: inputPixelBuffer,
                        pixelBufferPool: pixelBufferPool,
                        orientation: orientation,
                        outputSize: outputSize,
                        inputResolution: metadata.resolution,
                        inputTransform: metadata.transform,
                        horizontalWarpWidth: horizontalWarpWidth
                    )

                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    if !pixelBufferAdaptor.append(outputPixelBuffer, withPresentationTime: presentationTime) {
                        throw AppError.recoverableError(Self.processingFailureMessage)
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
                        throw AppError.recoverableError(Self.processingFailureMessage)
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

        if reader.error != nil {
            throw AppError.recoverableError(Self.processingFailureMessage)
        }

        if writer.error != nil {
            throw AppError.recoverableError(Self.processingFailureMessage)
        }
    }

    private static func evenSize(height: CGFloat, aspectWidth: CGFloat, aspectHeight: CGFloat) -> CGSize {
        let evenHeight = (height / 2).rounded() * 2
        let width = (evenHeight * aspectWidth / aspectHeight / 2).rounded() * 2
        return CGSize(width: width, height: evenHeight)
    }

    private static func evenSize(width: CGFloat, aspectWidth: CGFloat, aspectHeight: CGFloat) -> CGSize {
        let evenWidth = (width / 2).rounded() * 2
        let height = (evenWidth * aspectHeight / aspectWidth / 2).rounded() * 2
        return CGSize(width: evenWidth, height: height)
    }

    private static func getMetadata(from asset: AVAsset) async throws -> Metadata {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw AppError.recoverableError(Self.processingFailureMessage)
        }

        let (
            creationDate,
            duration,
            naturalSize,
            transform,
            frameRate,
            bitRate,
        ) = try await (
            asset.load(.creationDate),
            asset.load(.duration),
            videoTrack.load(.naturalSize),
            videoTrack.load(.preferredTransform),
            videoTrack.load(.nominalFrameRate),
            videoTrack.load(.estimatedDataRate),
        )

        let transformedSize = naturalSize.applying(transform)
        let resolution = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

        guard let creationDate = creationDate else {
            throw AppError.recoverableError(Self.processingFailureMessage)
        }

        return Metadata(
            creationDate: creationDate,
            duration: duration,
            resolution: resolution,
            transform: transform,
            frameRate: Double(frameRate),
            bitRate: Double(bitRate),
        )
    }

    private func processFrame(
        inputPixelBuffer: CVPixelBuffer,
        pixelBufferPool: CVPixelBufferPool,
        orientation: Orientation,
        outputSize: CGSize,
        inputResolution: CGSize,
        inputTransform: CGAffineTransform,
        horizontalWarpWidth: CGFloat
    ) throws -> CVPixelBuffer {
        // insertingIntermediate() forces Core Image to render the rotation into
        // a real intermediate buffer here, rather than fusing the transform
        // lazily into the custom kernels' samplers below — that fusion made
        // ROI negotiation with the hand-written kernels blow up and stall
        // frame processing. samplingNearest() keeps that render an exact pixel
        // copy, matching the nearest-neighbor sampling forced everywhere else
        // in this file, instead of Core Image's default interpolation.
        let inputImage = CIImage(cvPixelBuffer: inputPixelBuffer)
            .transformed(by: inputTransform)
            .samplingNearest()
            .insertingIntermediate()

        let outputImage: CIImage = switch orientation {
        case .horizontal:
            try processHorizontalFrame(inputImage: inputImage, inputResolution: inputResolution, outputSize: outputSize, warpWidth: horizontalWarpWidth)
        case .vertical:
            try processVerticalFrame(inputImage: inputImage, inputResolution: inputResolution, outputSize: outputSize)
        }

        var outputPixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &outputPixelBuffer)

        guard result == kCVReturnSuccess, let outputBuffer = outputPixelBuffer else {
            throw AppError.recoverableError(Self.processingFailureMessage)
        }

        // Carry over color space/transfer function attachments so the
        // render below reconstructs the same YCbCr matrix as the source.
        CVBufferPropagateAttachments(inputPixelBuffer, outputBuffer)

        context.render(outputImage, to: outputBuffer)

        return outputBuffer
    }

    private func processHorizontalFrame(inputImage: CIImage, inputResolution: CGSize, outputSize: CGSize, warpWidth: CGFloat) throws -> CIImage {
        // Horizontally, pre-scale by the same ratio the warp used to stretch by
        // (inputWidth -> warpWidth), so the warp's shape is unchanged but it now
        // lands back on outputSize.width (the input's own width) instead of warpWidth.
        // Vertically, downscale directly to outputSize.height — the kernel passes y
        // through unchanged, so once the source height already matches outputSize.height
        // no cropping is needed; the whole frame is kept, just compressed to fit 16:9.
        let horizontalScale = outputSize.width / warpWidth
        let verticalScale = outputSize.height / inputResolution.height
        let scaledImage = inputImage.transformed(by: CGAffineTransform(scaleX: horizontalScale, y: verticalScale))
        let inputSize = scaledImage.extent.size
        let sampler = CISampler(image: scaledImage, options: [Self.nearestSamplerFilterKey: Self.nearestSamplerFilterValue])

        guard let warpedImage = horizontalWarpKernel.apply(
            extent: CGRect(origin: .zero, size: outputSize),
            roiCallback: { _, _ in scaledImage.extent },
            arguments: [sampler, Float(inputSize.width), Float(outputSize.width)]
        ) else {
            throw AppError.recoverableError(Self.processingFailureMessage)
        }

        return warpedImage
    }

    private func processVerticalFrame(inputImage: CIImage, inputResolution: CGSize, outputSize: CGSize) throws -> CIImage {
        // Crop to a centered 5:8 rect, matching the previous crop shader pass
        let cropSize = Self.evenSize(height: inputResolution.height, aspectWidth: 5, aspectHeight: 8)
        let cropOrigin = CGPoint(
            x: floor((inputImage.extent.width - cropSize.width) / 2),
            y: floor((inputImage.extent.height - cropSize.height) / 2)
        )
        let croppedImage = inputImage
            .cropped(to: CGRect(origin: cropOrigin, size: cropSize))
            .transformed(by: CGAffineTransform(translationX: -cropOrigin.x, y: -cropOrigin.y))
        let sampler = CISampler(image: croppedImage, options: [Self.nearestSamplerFilterKey: Self.nearestSamplerFilterValue])

        guard let warpedImage = verticalWarpKernel.apply(
            extent: CGRect(origin: .zero, size: outputSize),
            roiCallback: { _, _ in croppedImage.extent },
            arguments: [
                sampler,
                Float(cropSize.width), Float(cropSize.height),
                Float(outputSize.width), Float(outputSize.height)
            ]
        ) else {
            throw AppError.recoverableError(Self.processingFailureMessage)
        }

        return warpedImage
    }
}
