import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import Photos
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
    @State private var showingDocumentPicker = false
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                switch appState {
                case .fileSelection:
                    FileSelectionView(
                        onSelectFile: {
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
            .navigationTitle("POV")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker { url in
                handleSelectedFile(url: url)
            }
        }
        .alert("Permission Required", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(permissionAlertMessage)
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
        Task {
            do {
                // Start accessing security-scoped resource
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                let asset = AVURLAsset(url: url)
                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { return }
                
                let naturalSize = try await videoTrack.load(.naturalSize)
                let transform = try await videoTrack.load(.preferredTransform)
                let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
                let duration = try await asset.load(.duration)
                
                // Get file extension for format display
                let ext = url.pathExtension
                
                // Calculate actual dimensions considering transform
                let transformedSize = naturalSize.applying(transform)
                let inputSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
                
                await MainActor.run {
                    self.videoInfo = VideoInfo(
                        resolution: inputSize,
                        duration: duration.seconds,
                        frameRate: Double(nominalFrameRate),
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
    
    private func processAndSaveVideo() {
        guard let inputVideoURL = selectedVideoURL else { return }
        
        // Check photo library permission first
        checkPhotoLibraryPermission { granted in
            if granted {
                self.startProcessing(inputURL: inputVideoURL)
            } else {
                self.permissionAlertMessage = "This app needs permission to save videos to your photo library. Please enable Photos access in Settings."
                self.showingPermissionAlert = true
            }
        }
    }
    
    private func checkPhotoLibraryPermission(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        switch status {
        case .authorized, .limited:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                DispatchQueue.main.async {
                    completion(newStatus == .authorized || newStatus == .limited)
                }
            }
        @unknown default:
            completion(false)
        }
    }
    
    private func startProcessing(inputURL: URL) {
        self.appState = .processing
        self.processingError = nil
        self.processingProgress = 0.0
        self.processingStartTime = Date()
        
        Task {
            await self.processVideo(inputURL: inputURL)
        }
    }
    
    private func processVideo(inputURL: URL) async {
        do {
            // Create temporary output URL
            let tempDirectory = FileManager.default.temporaryDirectory
            let outputURL = tempDirectory.appendingPathComponent("processed_video.mov")
            
            // Remove any existing file
            try? FileManager.default.removeItem(at: outputURL)
            
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
            
            // Save to photo library
            try await saveVideoToPhotoLibrary(url: outputURL)
            
            await MainActor.run {
                self.appState = .completed
                self.processingProgress = 1.0
                
                // Clean up temp file
                try? FileManager.default.removeItem(at: outputURL)
            }
            
        } catch {
            await MainActor.run {
                self.appState = .completed
                self.processingError = error.localizedDescription
                self.processingProgress = 0.0
            }
        }
    }
    
    private func saveVideoToPhotoLibrary(url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "VideoSaveError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save video to photo library"]))
                }
            }
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

struct DocumentPicker: UIViewControllerRepresentable {
    let onFileSelected: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie, .video, .quickTimeMovie, .mpeg4Movie], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onFileSelected(url)
        }
    }
}

struct FileSelectionView: View {
    let onSelectFile: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 16) {
                Image(systemName: "video.badge.plus")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Select a Video File")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Choose a video file from your device to get started")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 16) {
                Button(action: onSelectFile) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.title2)
                        Text("Browse Files")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                
                Text("Supports MP4, MOV, AVI and other video formats")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
        }
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
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
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
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    
                    Button(action: onClear) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("Start Over")
                        }
                        .font(.body)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                }
            }
            .padding(.horizontal)
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
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? quality.color.opacity(0.15) : Color.clear)
                        .frame(width: 50, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? quality.color : Color.secondary.opacity(0.3), lineWidth: 2)
                        )
                    
                    Image(systemName: quality.icon)
                        .font(.title2)
                        .foregroundColor(isSelected ? quality.color : .secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(quality.displayName)
                        .font(.headline)
                        .foregroundColor(isSelected ? quality.color : .primary)
                    
                    Text(quality.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(quality.color)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? quality.color.opacity(0.05) : Color(UIColor.systemBackground))
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

struct VideoInfoCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.15))
                    .frame(width: 50, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(color, lineWidth: 2)
                    )
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
            }
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
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
                        .font(.title2)
                        .foregroundColor(isSelected ? orientation.color : .secondary)
                }
                
                VStack(spacing: 4) {
                    Text(orientation.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
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
                    .fill(isSelected ? orientation.color.opacity(0.05) : Color(UIColor.systemBackground))
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
                    .rotationEffect(.degrees(-90))
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
            
            Text("Video will be saved to Photos when complete")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(30)
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
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
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
                    
                    Text("Your processed video has been saved to Photos.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            Button(action: onGoBack) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left")
                    Text("Process Another Video")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
        .padding(30)
    }
}

#Preview {
    ContentView()
}
