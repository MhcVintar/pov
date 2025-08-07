import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import PhotosUI

struct VideoInfo {
    let resolution: CGSize
    let duration: Double
    let frameRate: Double
    let format: String
}

enum AppState {
    case fileSelection
    case fileSelected
    case processing
    case completed
}

enum Orientation: String, CaseIterable {
    case horizontal = "Horizontal"
    case vertical = "Vertical"
    
    var displayName: String {
        return self.rawValue
    }
    
    var description: String {
        switch self {
        case .horizontal:
            return "Wide screen format"
        case .vertical:
            return "Portrait format"
        }
    }
    
    var icon: String {
        switch self {
        case .horizontal:
            return "rectangle"
        case .vertical:
            return "rectangle.portrait"
        }
    }
    
    var color: Color {
        switch self {
        case .horizontal:
            return .blue
        case .vertical:
            return .purple
        }
    }
}

enum OutputQuality: String, CaseIterable {
    case uhd4k = "4K"
    case k27 = "2.7K"
    case fullhd = "1080p"
    
    var displayName: String {
        return self.rawValue
    }
    
    var description: String {
        switch self {
        case .uhd4k:
            return "Ultra HD"
        case .k27:
            return "High Quality"
        case .fullhd:
            return "Standard HD"
        }
    }
    
    var icon: String {
        switch self {
        case .uhd4k:
            return "4k.tv"
        case .k27:
            return "tv"
        case .fullhd:
            return "tv.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .uhd4k:
            return .red
        case .k27:
            return .orange
        case .fullhd:
            return .green
        }
    }
    
    var size: CGSize {
        switch self {
        case .uhd4k:
            return CGSize(width: 3840.0, height: 2880.0)
        case .k27:
            return CGSize(width: 2704.0, height: 2028.0)
        case .fullhd:
            return CGSize(width: 1920.0, height: 1440.0)
        }
    }
}

struct ContentView: View {
    @State private var appState: AppState = .fileSelection
    @State private var selectedVideoURL: URL?
    @State private var processingProgress: Float = 0.0
    @State private var processingError: String?
    @State private var videoInfo: VideoInfo?
    @State private var processingStartTime = Date()
    @State private var selectedOrientation: Orientation = .horizontal
    @State private var selectedOutputQuality: OutputQuality = .k27
    @State private var showingPhotoPicker = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showingDocumentPicker = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                switch appState {
                case .fileSelection:
                    FileSelectionView(
                        onSelectFromPhotos: {
                            showingPhotoPicker = true
                        },
                        onSelectFromFiles: {
                            showingDocumentPicker = true
                        }
                    )
                    
                case .fileSelected:
                    FileSelectedView(
                        videoInfo: videoInfo,
                        selectedOrientation: $selectedOrientation,
                        selectedOutputQuality: $selectedOutputQuality,
                        onClear: {
                            clearSelection()
                        },
                        onProcess: {
                            processVideo()
                        }
                    )
                    
                case .processing:
                    ProcessingView(
                        processingProgress: processingProgress,
                        estimatedTimeRemaining: estimatedTimeRemaining(),
                        orientation: selectedOrientation,
                        outputQuality: selectedOutputQuality
                    )
                    
                case .completed:
                    CompletedView(
                        processingError: processingError,
                        onGoBack: {
                            goBackToStart()
                        }
                    )
                }
            }
            .padding()
            .navigationTitle("Video Processor")
            .navigationBarTitleDisplayMode(.inline)
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoPickerItem, matching: .videos)
        .fileImporter(
            isPresented: $showingDocumentPicker,
            allowedContentTypes: [.movie, .video, .quickTimeMovie, .mpeg4Movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    handleSelectedFile(url: url)
                }
            case .failure(let error):
                processingError = "Failed to select file: \(error.localizedDescription)"
            }
        }
        .onChange(of: photoPickerItem) { oldValue, newItem in
            Task {
                if let newItem = newItem {
                    do {
                        if let url = try await newItem.loadTransferable(type: VideoFile.self)?.url {
                            await MainActor.run {
                                handleSelectedFile(url: url)
                            }
                        }
                    } catch {
                        await MainActor.run {
                            processingError = "Failed to load video: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
    
    private func handleSelectedFile(url: URL) {
        selectedVideoURL = url
        processingError = nil
        processingProgress = 0.0
        
        // Load video information
        loadVideoInfo(from: url)
        
        // Move to file selected state
        appState = .fileSelected
    }
    
    private func loadVideoInfo(from url: URL) {
        Task.detached(priority: .userInitiated) {
            do {
                // Access security-scoped resource for file URLs
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                let asset = AVURLAsset(url: url)
                
                // Load tracks asynchronously
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let videoTrack = tracks.first else {
                    await MainActor.run {
                        self.processingError = "No video track found in the file"
                    }
                    return
                }
                
                // Load video properties concurrently for better performance
                async let naturalSize = videoTrack.load(.naturalSize)
                async let transform = videoTrack.load(.preferredTransform)
                async let nominalFrameRate = videoTrack.load(.nominalFrameRate)
                async let duration = asset.load(.duration)
                
                let (size, transformValue, frameRate, videoDuration) = try await (naturalSize, transform, nominalFrameRate, duration)
                
                // Get file extension for format display
                let ext = url.pathExtension
                
                // Calculate actual dimensions considering transform
                let transformedSize = size.applying(transformValue)
                let inputSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
                
                await MainActor.run {
                    self.videoInfo = VideoInfo(
                        resolution: inputSize,
                        duration: videoDuration.seconds,
                        frameRate: Double(frameRate),
                        format: ext.uppercased()
                    )
                }
            } catch {
                await MainActor.run {
                    self.processingError = "Failed to load video info: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func processVideo() {
        guard let inputVideoURL = selectedVideoURL else { return }
        
        self.appState = .processing
        self.processingError = nil
        self.processingProgress = 0.0
        self.processingStartTime = Date()
        
        Task {
            await self.processVideoFile(inputURL: inputVideoURL)
        }
    }
    
    private func processVideoFile(inputURL: URL) async {
        do {
            // Access security-scoped resource
            let accessing = inputURL.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    inputURL.stopAccessingSecurityScopedResource()
                }
            }
            
            // Generate output URL in documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let orientationPrefix = selectedOrientation == .horizontal ? "horizontal" : "vertical"
            let qualityPrefix = selectedOutputQuality.rawValue.lowercased()
            let outputURL = documentsPath.appendingPathComponent("pov_\(orientationPrefix)_\(qualityPrefix)_\(timestamp).MOV")
            
            // Create a simple video processor since VideoProcessor class wasn't provided
            try await processVideoWithAVFoundation(inputURL: inputURL, outputURL: outputURL)
            
            await MainActor.run {
                self.appState = .completed
                self.processingProgress = 1.0
            }
            
        } catch {
            await MainActor.run {
                self.appState = .completed
                self.processingError = error.localizedDescription
                self.processingProgress = 0.0
            }
        }
    }
    
    private func processVideoWithAVFoundation(inputURL: URL, outputURL: URL) async throws {
        let asset = AVURLAsset(url: inputURL)
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "VideoProcessing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        
        // Update progress periodically
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            DispatchQueue.main.async {
                self.processingProgress = exportSession.progress
            }
        }
        
        await exportSession.export()
        progressTimer.invalidate()
        
        switch exportSession.status {
        case .completed:
            await MainActor.run {
                self.processingProgress = 1.0
            }
        case .failed:
            throw exportSession.error ?? NSError(domain: "VideoProcessing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
        case .cancelled:
            throw NSError(domain: "VideoProcessing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export was cancelled"])
        default:
            throw NSError(domain: "VideoProcessing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown export error"])
        }
    }
    
    private func clearSelection() {
        selectedVideoURL = nil
        processingError = nil
        processingProgress = 0.0
        videoInfo = nil
        appState = .fileSelection
    }
    
    private func goBackToStart() {
        selectedVideoURL = nil
        processingError = nil
        processingProgress = 0.0
        videoInfo = nil
        appState = .fileSelection
    }
    
    private func estimatedTimeRemaining() -> String {
        guard processingProgress > 0.05 else { return "Calculating..." }
        
        let elapsed = Date().timeIntervalSince(processingStartTime)
        let estimated = elapsed / Double(processingProgress)
        let remaining = estimated - elapsed
        
        if remaining < 60 {
            return String(format: "~%.0f sec remaining", remaining)
        } else {
            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60
            return String(format: "~%d:%02d remaining", minutes, seconds)
        }
    }
}

// Helper struct for PhotosPicker
struct VideoFile: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let copy = URL.documentsDirectory.appending(path: "temp_\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return VideoFile(url: copy)
        }
    }
}

struct FileSelectionView: View {
    let onSelectFromPhotos: () -> Void
    let onSelectFromFiles: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                Image(systemName: "video.badge.plus")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                
                Text("Select a Video")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Choose a video file to process and convert")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 16) {
                // Photos button
                Button(action: onSelectFromPhotos) {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 20))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Choose from Photos")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Select from your photo library")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .foregroundColor(.primary)
                
                // Files button
                Button(action: onSelectFromFiles) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 20))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Browse Files")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Select from your device storage")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .foregroundColor(.primary)
            }
            
            VStack(spacing: 8) {
                Text("Supported formats:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("MP4, MOV, AVI and other video formats")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
    }
}

struct FileSelectedView: View {
    let videoInfo: VideoInfo?
    @Binding var selectedOrientation: Orientation
    @Binding var selectedOutputQuality: OutputQuality
    let onClear: () -> Void
    let onProcess: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let info = videoInfo {
                    VStack(spacing: 16) {
                        Text("Video Information")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                            VideoInfoCard(
                                icon: "viewfinder",
                                title: "Resolution",
                                value: "\(Int(info.resolution.width)) × \(Int(info.resolution.height))",
                                color: .blue
                            )
                            
                            VideoInfoCard(
                                icon: "clock.fill",
                                title: "Duration",
                                value: formatDuration(info.duration),
                                color: .green
                            )
                            
                            VideoInfoCard(
                                icon: "speedometer",
                                title: "Frame Rate",
                                value: "\(String(format: "%.0f", info.frameRate)) fps",
                                color: .orange
                            )
                            
                            VideoInfoCard(
                                icon: "doc.fill",
                                title: "Format",
                                value: info.format,
                                color: .purple
                            )
                        }
                    }
                }
                
                // Orientation Selection
                VStack(spacing: 16) {
                    Text("Output Orientation")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 16) {
                        ForEach(Orientation.allCases, id: \.self) { orientation in
                            OrientationCard(
                                orientation: orientation,
                                isSelected: selectedOrientation == orientation
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedOrientation = orientation
                                }
                            }
                        }
                    }
                }
                
                // Output Quality Selection
                VStack(spacing: 16) {
                    Text("Output Quality")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 12) {
                        ForEach(OutputQuality.allCases, id: \.self) { quality in
                            QualityModeCard(
                                quality: quality,
                                isSelected: selectedOutputQuality == quality
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedOutputQuality = quality
                                }
                            }
                        }
                    }
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: onProcess) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Process Video")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onClear) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("Start Over")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

struct QualityModeCard: View {
    let quality: OutputQuality
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? quality.color.opacity(0.15) : Color(.systemGray6))
                        .frame(width: 50, height: 35)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? quality.color : Color.clear, lineWidth: 2)
                        )
                    
                    Image(systemName: quality.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isSelected ? quality.color : .secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(quality.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? quality.color : .primary)
                    
                    Text(quality.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(quality.color)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? quality.color.opacity(0.05) : Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? quality.color.opacity(0.4) : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

struct VideoInfoCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 50, height: 35)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(color, lineWidth: 2)
                    )
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(color)
            }
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(value)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}

struct OrientationCard: View {
    let orientation: Orientation
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? orientation.color.opacity(0.15) : Color(.systemGray6))
                        .frame(width: 50, height: 35)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? orientation.color : Color.clear, lineWidth: 2)
                        )
                    
                    Image(systemName: orientation.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isSelected ? orientation.color : .secondary)
                }
                
                VStack(spacing: 4) {
                    Text(orientation.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isSelected ? orientation.color : .primary)
                    
                    Text(orientation.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? orientation.color.opacity(0.05) : Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? orientation.color.opacity(0.4) : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

struct ProcessingView: View {
    let processingProgress: Float
    let estimatedTimeRemaining: String
    let orientation: Orientation
    let outputQuality: OutputQuality
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Processing Video...")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            VStack(spacing: 8) {
                Text("Orientation: \(orientation.displayName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Quality: \(outputQuality.displayName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Circular Progress View
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 12)
                    .frame(width: 120, height: 120)
                
                // Progress circle
                Circle()
                    .trim(from: 0, to: CGFloat(processingProgress))
                    .stroke(
                        Color.blue,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90)) // Start from top
                    .animation(.easeInOut(duration: 0.3), value: processingProgress)
                
                // Percentage text in center
                Text("\(Int(processingProgress * 100))%")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            if processingProgress > 0 {
                Text(estimatedTimeRemaining)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
    }
}

struct CompletedView: View {
    let processingError: String?
    let onGoBack: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            if let error = processingError {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    
                    Text("Processing Failed")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            } else {
                // Success state
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("Video Processed Successfully!")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                    
                    Text("Your video has been saved to your device.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Button(action: onGoBack) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left")
                    Text("Process Another Video")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }
}

#Preview {
    ContentView()
}
