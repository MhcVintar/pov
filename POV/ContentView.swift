//
//  ContentView.swift
//  POV
//
//  Created by Miha Vintar on 28. 7. 25.
//

import SwiftUI
import AVFoundation

enum AppState {
    case fileSelection
    case fileSelected
    case processing
    case completed
}

struct ContentView: View {
    @State private var appState: AppState = .fileSelection
    @State private var selectedFilePath: String = "No file selected"
    @State private var selectedVideoURL: URL?
    @State private var processingProgress: Float = 0.0
    @State private var processingError: String?
    @State private var videoInfo: VideoInfo?
    @State private var processingStartTime = Date()
    
    var body: some View {
        VStack(spacing: 20) {
            switch appState {
            case .fileSelection:
                FileSelectionView {
                    openFileDialog()
                }
                
            case .fileSelected:
                FileSelectedView(
                    selectedFilePath: selectedFilePath,
                    videoInfo: videoInfo,
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
                    estimatedTimeRemaining: estimatedTimeRemaining()
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
        .padding(30)
        .frame(minWidth: 500, minHeight: 400)
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
                    selectedFilePath = url.path
                    selectedVideoURL = url
                    processingError = nil
                    processingProgress = 0.0
                    
                    // Load video information
                    loadVideoInfo(from: url)
                    
                    // Move to file selected state
                    appState = .fileSelected
                }
            }
        }
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
                var shortName = name.count > 15 ? String(name.prefix(15)) + "..." : name
                shortName = "\(shortName).\(ext)"
                
                // Calculate actual dimensions considering transform
                let transformedSize = naturalSize.applying(transform)
                let inputSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
                let outputSize = CGSize(width: inputSize.height * 16/9, height: inputSize.height)
                
                await MainActor.run {
                    self.videoInfo = VideoInfo(
                        name: shortName,
                        resolution: inputSize,
                        outputSize: outputSize,
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
        
        // Generate unique file name
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        savePanel.nameFieldStringValue = "pov_export_\(timestamp).MOV"
        
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
        let converterController = VideoConverterViewController()
        converterController.setupConverter()
        
        do {
            try await converterController.convertVideo(
                inputPath: inputURL.path,
                outputPath: outputURL.path
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

// MARK: - State Views

struct FileSelectionView: View {
    let onSelectFile: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Select a video file to get started")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Button("Choose Video File", action: onSelectFile)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

struct FileSelectedView: View {
    let selectedFilePath: String
    let videoInfo: VideoInfo?
    let onClear: () -> Void
    let onProcess: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // File info section
            VStack(alignment: .center, spacing: 12) {
                if let info = videoInfo {
                    VideoInfoView(videoInfo: info)
                }
            }
            
            // Action buttons side by side
            HStack(spacing: 20) {
                Button("Clear Selection", action: onClear)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                
                Button("Process & Save Video", action: onProcess)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }
}

struct ProcessingView: View {
    let processingProgress: Float
    let estimatedTimeRemaining: String
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Processing Video...")
                .font(.title)
                .foregroundColor(.blue)
            
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
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(40)
    }
}

struct CompletedView: View {
    let processingError: String?
    let onGoBack: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            if let error = processingError {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    
                    Text("Processing Failed")
                        .font(.title)
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
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    
                    Text("Your video has been saved successfully.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            
            Button("Go Back", action: onGoBack)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
    }
}

// MARK: - Subviews

struct VideoInfoView: View {
    let videoInfo: VideoInfo
    
    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text("Video Information:")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            InfoRow(label: "Name:", value: "\(videoInfo.name)")
            InfoRow(label: "Resolution:", value: "\(Int(videoInfo.resolution.width)) × \(Int(videoInfo.resolution.height))")
            InfoRow(label: "Duration:", value: formatDuration(videoInfo.duration))
            InfoRow(label: "Frame Rate:", value: "\(String(format: "%.1f", videoInfo.frameRate)) fps")
            
            HStack {
                Text("Output Size:")
                Text("\(Int(videoInfo.outputSize.width)) × \(Int(videoInfo.outputSize.height))")
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
            .font(.caption)
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
        .font(.caption)
    }
}

struct VideoInfo {
    let name: String
    let resolution: CGSize
    let outputSize: CGSize
    let duration: Double
    let frameRate: Double
}

#Preview {
    ContentView()
}
