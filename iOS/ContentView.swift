import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import UIKit
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
    @State private var showingFilePicker = false
    @State private var outputURL: URL?

    var body: some View {
        VStack(spacing: 16) {
            switch appState {
            case .fileSelection:
                FileSelectionView(onSelectFile: {
                    showingPicker = true
                })

            case .fileSelected:
                FileSelectedView(
                    videoInfo: videoInfo,
                    selectedOrientation: $selectedOrientation,
                    selectedOutputQuality: $selectedOutputQuality,
                    onClear: { clearSelection() },
                    onProcess: { processAndSaveVideo() }
                )

            case .processing:
                ProcessingView(
                    processingProgress: processingProgress,
                    estimatedTimeRemaining: estimatedTimeRemaining(),
                    orientation: selectedOrientation,
                    outputQuality: selectedOutputQuality
                )

            case .completed:
                CompletedView(processingError: processingError) {
                    goBackToStart()
                }
            }
        }
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoPicker { url in
                if let url = url {
                    handleSelectedFile(url: url)
                }
            }
        }
        .sheet(isPresented: $showingFilePicker) {
            DocumentPicker { url in
                if let url = url {
                    handleSelectedFile(url: url)
                }
            }
        }
    }

    private func handleSelectedFile(url: URL) {
        selectedVideoURL = url
        processingError = nil
        processingProgress = 0.0
        appState = .fileSelected
    }

    private func processAndSaveVideo() {
        guard let inputVideoURL = selectedVideoURL else { return }
        
        // On iOS, save to temporary directory first
        let filename = "processed_\(UUID().uuidString).mov"
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        self.outputURL = output
        startProcessing(inputURL: inputVideoURL, outputURL: output)
    }

    private func startProcessing(inputURL: URL, outputURL: URL) {
        appState = .processing
        processingError = nil
        processingProgress = 0.0
        processingStartTime = Date()

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

            try await videoProcessor.convertVideo(inputURL: inputURL, outputURL: outputURL) { progress in
                DispatchQueue.main.async {
                    self.processingProgress = progress
                }
            }

            // Save to Photos
            await saveToPhotos(url: outputURL)

            await MainActor.run {
                appState = .completed
                processingProgress = 1.0
            }
        } catch {
            await MainActor.run {
                appState = .completed
                processingError = error.localizedDescription
                processingProgress = 0.0
            }
        }
    }

    private func saveToPhotos(url: URL) async {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }, completionHandler: { success, error in
            if let error = error {
                print("Error saving to Photos: \(error)")
            }
        })
    }

    private func clearSelection() {
        selectedVideoURL = nil
        processingError = nil
        processingProgress = 0.0
        videoInfo = nil
        appState = .fileSelection
    }

    private func goBackToStart() {
        clearSelection()
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

struct PhotoPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var onPick: (URL?) -> Void
        
        init(onPick: @escaping (URL?) -> Void) {
            self.onPick = onPick
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else {
                onPick(nil)
                return
            }
            
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    if let url = url {
                        // Copy to temporary directory to keep it alive
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                        try? FileManager.default.copyItem(at: url, to: tempURL)
                        DispatchQueue.main.async {
                            self.onPick(tempURL)
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.onPick(nil)
                        }
                    }
                }
            } else {
                onPick(nil)
            }
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie, .video], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL?) -> Void
        
        init(onPick: @escaping (URL?) -> Void) {
            self.onPick = onPick
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}

struct FileSelectionView: View {
    let onSelectFile: () -> Void
    let onSelectPhoto: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Select a video to get started")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: onSelectFile) {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                    Text("Browse Files")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(LinearGradient(colors: [Color.blue, Color.blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .padding(.horizontal, 20)
            
            Button(action: onSelectPhoto) {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                    Text("Browse Photos")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(LinearGradient(colors: [Color.purple, Color.purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .purple.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .padding(.horizontal, 20)
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
        VStack(spacing: 20) {
            if let info = videoInfo {
                VStack(spacing: 12) {
                    Text("Video Information")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
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
                        }
                        
                        HStack(spacing: 12) {
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
            }
            
            // Orientation Selection
            VStack(spacing: 12) {
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
                            .fill(Color(uiColor: .systemBackground))
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
                    .fill(isSelected ? quality.color.opacity(0.05) : Color(uiColor: .systemBackground))
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
                    .frame(width: 60, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(color, lineWidth: 2)
                    )
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(color)
            }
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(value)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .systemBackground))
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
                    .fill(isSelected ? orientation.color.opacity(0.05) : Color(uiColor: .systemBackground))
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

#Preview {
    ContentView()
}
