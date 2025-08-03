import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

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
    @State private var selectedFilePath: String = "No file selected"
    @State private var selectedVideoURL: URL?
    @State private var processingProgress: Float = 0.0
    @State private var processingError: String?
    @State private var videoInfo: VideoInfo?
    @State private var processingStartTime = Date()
    @State private var selectedOrientation: Orientation = .horizontal
    @State private var selectedOutputQuality: OutputQuality = .k27
    
    var body: some View {
        VStack(spacing: 16) {
            switch appState {
            case .fileSelection:
                FileSelectionView(
                    onSelectFile: {
                        openFileDialog()
                    },
                    onDropFile: { url in
                        handleDroppedFile(url: url)
                    }
                )
                
            case .fileSelected:
                FileSelectedView(
                    selectedFilePath: selectedFilePath,
                    videoInfo: videoInfo,
                    selectedOrientation: $selectedOrientation,
                    selectedOutputQuality: $selectedOutputQuality,
                    onClear: {
                        clearSelection()
                    },
                    onProcess: {
                        processAndSaveVideo()
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
        .padding(20)
        .frame(minWidth: 380, maxWidth: 420, minHeight: 400)
    }
    
    private func openFileDialog() {
        let panel = NSOpenPanel()
        
        // Configure the file dialog for videos
        panel.title = "Choose a video file"
        panel.showsHiddenFiles = false
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .quickTimeMovie, .mpeg4Movie]
        
        // Show the dialog
        panel.begin { response in
            if response == .OK {
                if let url = panel.url {
                    handleSelectedFile(url: url)
                }
            }
        }
    }
    
    private func handleDroppedFile(url: URL) {
        // Validate that it's a video file
        let allowedTypes: [UTType] = [.movie, .video, .quickTimeMovie, .mpeg4Movie]
        let fileType = UTType(filenameExtension: url.pathExtension)
        
        let isValidVideo = allowedTypes.contains { allowedType in
            fileType?.conforms(to: allowedType) == true
        }
        
        if isValidVideo {
            handleSelectedFile(url: url)
        } else {
            processingError = "Please select a valid video file"
        }
    }
    
    private func handleSelectedFile(url: URL) {
        selectedFilePath = url.path
        selectedVideoURL = url
        processingError = nil
        processingProgress = 0.0
        
        // Load video information
        loadVideoInfo(from: url)
        
        // Move to file selected state
        appState = .fileSelected
    }
    
    private func loadVideoInfo(from url: URL) {
        Task {
            do {
                let asset = AVURLAsset(url: url)
                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { return }
                
                let naturalSize = try await videoTrack.load(.naturalSize)
                let transform = try await videoTrack.load(.preferredTransform)
                let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
                let duration = try await asset.load(.duration)
                
                // Parse file name
                let name = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension
                var shortName = name.count > 25 ? String(name.prefix(19)) + "..." + String(name.suffix(3)) : name
                shortName = "\(shortName).\(ext)"
                
                // Calculate actual dimensions considering transform
                let transformedSize = naturalSize.applying(transform)
                let inputSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
                
                await MainActor.run {
                    self.videoInfo = VideoInfo(
                        name: shortName,
                        resolution: inputSize,
                        duration: duration.seconds,
                        frameRate: Double(nominalFrameRate)
                    )
                }
            } catch {
                await MainActor.run {
                    self.processingError = "Failed to load video info: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func processAndSaveVideo() {
        guard let inputVideoURL = selectedVideoURL else { return }
        
        // First show save dialog to get the output path
        let savePanel = NSSavePanel()
        savePanel.title = "Save Processed Video"
        savePanel.allowedContentTypes = [.quickTimeMovie, .mpeg4Movie]
        
        // Generate unique file name with quality information
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let orientationPrefix = selectedOrientation == .horizontal ? "horizontal" : "vertical"
        let qualityPrefix = selectedOutputQuality.rawValue.lowercased()
        savePanel.nameFieldStringValue = "pov_\(orientationPrefix)_\(qualityPrefix)_\(timestamp).MOV"
        
        savePanel.begin { response in
            guard response == .OK, let outputURL = savePanel.url else { return }
            
            self.startProcessing(inputURL: inputVideoURL, outputURL: outputURL)
        }
    }
    
    private func startProcessing(inputURL: URL, outputURL: URL) {
        self.appState = .processing
        self.processingError = nil
        self.processingProgress = 0.0
        self.processingStartTime = Date()
        
        Task {
            await self.processVideo(inputURL: inputURL, outputURL: outputURL)
        }
    }
    
    private func processVideo(inputURL: URL, outputURL: URL) async {
        do {
            let videoProcessor = try VideoProcessor(
                orientation: selectedOrientation,
                outputQuality: selectedOutputQuality
            )
            
            try await videoProcessor.convertVideo(
                inputURL: inputURL,
                outputURL: outputURL
            ) { progress in
                // This closure is called from the video processor with progress updates
                DispatchQueue.main.async {
                    self.processingProgress = progress
                }
            }
            
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
    
    private func clearSelection() {
        selectedFilePath = "No file selected"
        selectedVideoURL = nil
        processingError = nil
        processingProgress = 0.0
        videoInfo = nil
        appState = .fileSelection
    }
    
    private func goBackToStart() {
        selectedFilePath = "No file selected"
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

struct FileSelectionView: View {
    let onSelectFile: () -> Void
    let onDropFile: (URL) -> Void
    @State private var isDragOver = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Select a video file to get started")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // Drag and Drop Area
            VStack(spacing: 16) {
                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isDragOver ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                        .frame(height: 160)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    isDragOver ? Color.blue : Color.gray.opacity(0.3),
                                    style: StrokeStyle(lineWidth: 2, dash: [8])
                                )
                        )
                    
                    // Content
                    VStack(spacing: 12) {
                        Image(systemName: isDragOver ? "video.fill.badge.plus" : "video.badge.plus")
                            .font(.system(size: 36))
                            .foregroundColor(isDragOver ? .blue : .gray)
                        
                        VStack(spacing: 6) {
                            Text("Drag and drop your video file here")
                                .font(.subheadline)
                                .foregroundColor(isDragOver ? .blue : .primary)
                                .multilineTextAlignment(.center)
                            
                            Text("Supports MP4, MOV, AVI and other formats")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                    guard let provider = providers.first else { return false }
                    
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                        guard let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                        
                        DispatchQueue.main.async {
                            onDropFile(url)
                        }
                    }
                    return true
                }
                
                // Or separator
                HStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                    
                    Text("or")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                }
                
                // Browse button - Updated styling
                Button(action: onSelectFile) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                        Text("Browse Files")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FileSelectedView: View {
    let selectedFilePath: String
    let videoInfo: VideoInfo?
    @Binding var selectedOrientation: Orientation
    @Binding var selectedOutputQuality: OutputQuality
    let onClear: () -> Void
    let onProcess: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Video Info Card
            if let info = videoInfo {
                VStack(spacing: 16) {
                    // Header with video name
                    VStack(spacing: 4) {
                        Text(info.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .lineLimit(1)
                        
                        Text("Ready to process")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Video specs in a grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        VideoSpecCard(
                            icon: "viewfinder",
                            title: "Resolution",
                            value: "\(Int(info.resolution.width)) × \(Int(info.resolution.height))",
                            color: .blue
                        )
                        
                        VideoSpecCard(
                            icon: "clock.fill",
                            title: "Duration",
                            value: formatDuration(info.duration),
                            color: .green
                        )
                        
                        VideoSpecCard(
                            icon: "speedometer",
                            title: "Frame Rate",
                            value: "\(String(format: "%.0f", info.frameRate)) fps",
                            color: .orange
                        )
                        
                        VideoSpecCard(
                            icon: "doc.fill",
                            title: "Format",
                            value: info.name.components(separatedBy: ".").last?.uppercased() ?? "VIDEO",
                            color: .purple
                        )
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                )
            }
            
            // Orientation Selection
            VStack(spacing: 12) {
                Text("Choose Orientation")
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
            VStack(spacing: 12) {
                Text("Output Quality")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                HStack(spacing: 12) {
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
            
            Spacer().frame(height: 8)
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: onClear) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Start Over")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                
                Button(action: onProcess) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Process Video")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }
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
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? quality.color.opacity(0.15) : Color.clear)
                        .frame(width: 60, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? quality.color : Color.secondary.opacity(0.3), lineWidth: 2)
                        )
                    
                    Image(systemName: quality.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isSelected ? quality.color : .secondary)
                }
                
                VStack(spacing: 4) {
                    Text(quality.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isSelected ? quality.color : .primary)
                    
                    Text(quality.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? quality.color.opacity(0.05) : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? quality.color.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

struct VideoSpecCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
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
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? orientation.color.opacity(0.15) : Color.clear)
                        .frame(width: 60, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? orientation.color : Color.secondary.opacity(0.3), lineWidth: 2)
                        )
                    
                    Image(systemName: orientation.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isSelected ? orientation.color : .secondary)
                }
                
                VStack(spacing: 4) {
                    Text(orientation.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isSelected ? orientation.color : .primary)
                    
                    Text(orientation.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? orientation.color.opacity(0.05) : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? orientation.color.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
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
        VStack(spacing: 12) {
            Text("Processing Video...")
                .font(.title2)
                .foregroundColor(.blue)
            
            VStack(spacing: 4) {
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
                    .stroke(Color.blue.opacity(0.2), lineWidth: 10)
                    .frame(width: 100, height: 100)
                
                // Progress circle
                Circle()
                    .trim(from: 0, to: CGFloat(processingProgress))
                    .stroke(
                        Color.blue,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90)) // Start from top
                    .animation(.easeInOut(duration: 0.3), value: processingProgress)
                
                // Percentage text in center
                Text("\(Int(processingProgress * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            if processingProgress > 0 {
                Text(estimatedTimeRemaining)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(30)
    }
}

struct CompletedView: View {
    let processingError: String?
    let onGoBack: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            if let error = processingError {
                // Error state
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    
                    Text("Processing Failed")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            } else {
                // Success state
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    
                    Text("Video Processed Successfully!")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                    
                    Text("Your video has been saved successfully.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            // Updated Go Back button styling
            Button(action: onGoBack) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left")
                    Text("Go Back")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(30)
    }
}

struct VideoInfoView: View {
    let videoInfo: VideoInfo
    let orientation: Orientation
    
    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Text("Video Information:")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            InfoRow(label: "Name:", value: "\(videoInfo.name)")
            InfoRow(label: "Resolution:", value: "\(Int(videoInfo.resolution.width)) × \(Int(videoInfo.resolution.height))")
            InfoRow(label: "Duration:", value: formatDuration(videoInfo.duration))
            InfoRow(label: "Frame Rate:", value: "\(String(format: "%.1f", videoInfo.frameRate)) fps")
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Text(value)
                .fontWeight(.medium)
        }
        .font(.callout)
    }
}

struct VideoInfo {
    let name: String
    let resolution: CGSize
    let duration: Double
    let frameRate: Double
}

#Preview {
    ContentView()
}
