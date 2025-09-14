import SwiftUI
import AVFoundation
import AudioToolbox
import Photos
import PhotosUI

struct VideoInfo {
    let resolution: CGSize
    let duration: Double
}

enum NavigationDestination: Hashable {
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
    @State private var navigationPath = NavigationPath()
    @State private var selectedPHAsset: PHAsset?
    @State private var processingProgress: Float = 0.0
    @State private var processingCancelled: Bool = false
    @State private var processingError: String?
    @State private var videoInfo: VideoInfo?
    @State private var processingStartTime = Date()
    @State private var selectedOrientation: Orientation = .horizontal
    @State private var selectedOutputQuality: OutputQuality = .k27
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            FileSelectionView(
                selectedPhotoItem: $selectedPhotoItem
            )
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .fileSelected:
                    FileSelectedView(
                        videoInfo: $videoInfo,
                        selectedOrientation: $selectedOrientation,
                        selectedOutputQuality: $selectedOutputQuality,
                        onProcess: {
                            processAndSaveVideo()
                        }
                    )
                    .onDisappear() {
                        selectedPhotoItem = nil
                        selectedPHAsset = nil
                    }
                case .processing:
                    ProcessingView(
                        processingProgress: processingProgress,
                        estimatedTimeRemaining: estimatedTimeRemaining(),
                        orientation: selectedOrientation,
                        outputQuality: selectedOutputQuality
                    )
                    .onAppear() {
                        UIApplication.shared.isIdleTimerDisabled = true
                    }
                    .onDisappear() {
                        UIApplication.shared.isIdleTimerDisabled = false
                        processingCancelled = true
                    }
                case .completed:
                    CompletedView(
                        processingError: processingError,
                    )
                }
            }
        }
        .onChange(of: selectedPhotoItem) {
            if let selectedPhotoItem = selectedPhotoItem {
                handleSelectedPhotoItem(item: selectedPhotoItem)
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
    
    // Method to get PHAsset from PhotosPickerItem
    private func getPHAsset(from item: PhotosPickerItem) async -> PHAsset? {
        // Get the asset identifier from the PhotosPickerItem
        guard let assetIdentifier = item.itemIdentifier else { return nil }
        
        // Fetch the PHAsset using the identifier
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        return fetchResult.firstObject
    }
    
    private func handleSelectedPhotoItem(item: PhotosPickerItem) {
        processingError = nil
        processingProgress = 0.0
        processingCancelled = false
        
        guard let assetIdentifier = item.itemIdentifier else { return }
        selectedPHAsset = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil).firstObject
        if let asset = selectedPHAsset {
            videoInfo = VideoInfo(
                resolution: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                duration: asset.duration
            )
        }

        DispatchQueue.main.async {
            navigationPath.append(NavigationDestination.fileSelected)
        }
    }
    
    private func processAndSaveVideo() {
        guard let inputPHAsset = selectedPHAsset else { return }
        
        // Check photo library permission first
        checkPhotoLibraryPermission { granted in
            if granted {
                self.startProcessing(inputAsset: inputPHAsset)
            } else {
                self.permissionAlertMessage = "This app needs permission to access and save videos to your photo library. Please enable Photos access in Settings."
                self.showingPermissionAlert = true
            }
        }
    }
    
    private func checkPhotoLibraryPermission(completion: @escaping (Bool) -> Void) {
        // Check both read and write permissions since we're using PHAssets
        let readStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let writeStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        // We need read access to work with PHAssets and write access to save processed videos
        let hasReadAccess = readStatus == .authorized || readStatus == .limited
        let hasWriteAccess = writeStatus == .authorized || writeStatus == .limited
        
        if hasReadAccess && hasWriteAccess {
            completion(true)
        } else if readStatus == .denied || readStatus == .restricted || writeStatus == .denied || writeStatus == .restricted {
            completion(false)
        } else {
            // Request read/write permission
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    let hasAccess = newStatus == .authorized || newStatus == .limited
                    completion(hasAccess)
                }
            }
        }
    }
    
    private func startProcessing(inputAsset: PHAsset) {
        navigationPath.append(NavigationDestination.processing)
        processingError = nil
        processingProgress = 0.0
        processingCancelled = false
        processingStartTime = Date()
        
        Task {
            await self.processVideo(inputAsset: inputAsset)
        }
    }
    
    private func processVideo(inputAsset: PHAsset) async {
        do {
            // Create temporary output URL
            let tempDirectory = FileManager.default.temporaryDirectory
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let dateString = dateFormatter.string(from: Date())
            let outputURL = tempDirectory.appendingPathComponent("pov_\(dateString).MOV")
            
            // Remove any existing file
            try? FileManager.default.removeItem(at: outputURL)
            
            let videoProcessor = try VideoProcessor(
                orientation: selectedOrientation,
                outputQuality: selectedOutputQuality
            )
            
            try await videoProcessor.convertVideo(
                inputAsset: inputAsset,
                outputURL: outputURL,
                isCancelled: { self.processingCancelled }
            ) { progress in
                // This closure is called from the video processor with progress updates
                DispatchQueue.main.async {
                    self.processingProgress = progress
                }
            }
            
            if !self.processingCancelled {
                // Save to photo library
                try await saveVideoToPhotoLibrary(url: outputURL)
                
                // Play alert sound and vibrate
                AudioServicesPlayAlertSoundWithCompletion(1016, nil)
                AudioServicesPlaySystemSoundWithCompletion(kSystemSoundID_Vibrate, nil)
                
                await MainActor.run {
                    self.navigationPath = NavigationPath([NavigationDestination.completed])
                    self.processingProgress = 1.0
                }
            }
            
            // Clean up temp files
            await MainActor.run {
                try? FileManager.default.removeItem(at: outputURL)
            }
            
        } catch {
            await MainActor.run {
                self.navigationPath = NavigationPath([NavigationDestination.completed])
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
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @State private var showPicker = false

    var body: some View {
        ZStack {
            Color.clear // stretch gesture area full screen
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 20, coordinateSpace: .local)
                        .onEnded { value in
                            if value.translation.height < 0 {
                                showPicker = true
                            }
                        }
                )

            VStack(spacing: 30) {
                VStack(spacing: 16) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Select a Video File")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Swipe up to open your Photos library and choose a video")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
        .photosPicker(isPresented: $showPicker,
                      selection: $selectedPhotoItem,
                      matching: .videos,
                      photoLibrary: .shared())
    }
}

struct FileSelectedView: View {
    @Binding var videoInfo: VideoInfo?
    @Binding var selectedOrientation: Orientation
    @Binding var selectedOutputQuality: OutputQuality
    let onProcess: () -> Void
    
    var body: some View {
        ScrollView(showsIndicators: false) {
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
                    
                    HStack(spacing: 16) {
                        ForEach(OutputQuality.allCases, id: \.self) { quality in
                            QualityCard(
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
                
                // Process button
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

struct QualityCard: View {
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
                        .font(.title2)
                        .foregroundColor(isSelected ? quality.color : .secondary)
                }
                
                VStack(spacing: 4) {
                    Text(quality.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
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
            Text("Processing Video")
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
            
            Text("Make sure to stay on current screen")
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
        }
        .padding(30)
    }
}

#Preview {
    ContentView()
}
