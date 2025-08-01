//
//  ContentView.swift
//  POV
//
//  Created by Miha Vintar on 28. 7. 25.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var selectedFilePath: String = "No file selected"
    @State private var selectedVideoURL: URL?
    @State private var isProcessing = false
    @State private var processingComplete = false
    @State private var processingProgress: Float = 0.0
    @State private var processingError: String?
    @State private var videoInfo: VideoInfo?
    @State private var processingStartTime = Date()
    
    var body: some View {
        VStack(spacing: 20) {
            HeaderView()
            
            FileSelectionButton {
                openFileDialog()
            }
            
            if selectedFilePath != "No file selected" {
                FileInfoSection(
                    selectedFilePath: selectedFilePath,
                    videoInfo: videoInfo
                )
                
                ProcessingSection(
                    isProcessing: isProcessing,
                    processingProgress: processingProgress,
                    processingComplete: processingComplete,
                    processingError: processingError,
                    estimatedTimeRemaining: estimatedTimeRemaining(),
                    onProcessVideo: {
                        processAndSaveVideo()
                    }
                )
                
                ClearButton {
                    clearSelection()
                }
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
                    processingComplete = false
                    processingError = nil
                    processingProgress = 0.0
                    
                    // Load video information
                    loadVideoInfo(from: url)
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
                
                // Calculate actual dimensions considering transform
                let transformedSize = naturalSize.applying(transform)
                let inputSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
                let outputSize = CGSize(width: inputSize.height * 16/9, height: inputSize.height)
                
                await MainActor.run {
                    self.videoInfo = VideoInfo(
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
        self.isProcessing = true
        self.processingComplete = false
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
                self.isProcessing = false
                self.processingComplete = true
                self.processingProgress = 1.0
            }
            
        } catch {
            await MainActor.run {
                self.isProcessing = false
                self.processingError = error.localizedDescription
                self.processingProgress = 0.0
            }
        }
    }
    
    private func clearSelection() {
        selectedFilePath = "No file selected"
        selectedVideoURL = nil
        processingComplete = false
        processingError = nil
        processingProgress = 0.0
        videoInfo = nil
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
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

// MARK: - Subviews

struct HeaderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Video Aspect Ratio Converter")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Convert 4:3 videos to 16:9 with SuperView transformation")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

struct FileSelectionButton: View {
    let action: () -> Void
    
    var body: some View {
        Button("Choose Video File", action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
    }
}

struct FileInfoSection: View {
    let selectedFilePath: String
    let videoInfo: VideoInfo?
    
    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            FilePathView(selectedFilePath: selectedFilePath)
            
            if let info = videoInfo {
                VideoInfoView(videoInfo: info)
            }
        }
    }
}

struct FilePathView: View {
    let selectedFilePath: String
    
    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("Selected File:")
                .font(.headline)
            
            Text(selectedFilePath)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
        }
    }
}

struct VideoInfoView: View {
    let videoInfo: VideoInfo
    
    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text("Video Information:")
                .font(.subheadline)
                .fontWeight(.semibold)
            
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

struct ProcessingSection: View {
    let isProcessing: Bool
    let processingProgress: Float
    let processingComplete: Bool
    let processingError: String?
    let estimatedTimeRemaining: String
    let onProcessVideo: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            if isProcessing {
                ProcessingView(
                    processingProgress: processingProgress,
                    estimatedTimeRemaining: estimatedTimeRemaining
                )
            } else {
                ProcessButton(action: onProcessVideo)
            }
            
            if processingComplete {
                SuccessMessage()
            }
            
            if let error = processingError {
                ErrorMessage(error: error)
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
                .font(.headline)
                .foregroundColor(.blue)
            
            // Circular Progress View
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 8)
                    .frame(width: 80, height: 80)
                
                // Progress circle
                Circle()
                    .trim(from: 0, to: CGFloat(processingProgress))
                    .stroke(
                        Color.blue,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
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
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}

struct ProcessButton: View {
    let action: () -> Void
    
    var body: some View {
        Button("Process & Save Video", action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
    }
}

struct SuccessMessage: View {
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Video processed and saved successfully!")
                .foregroundColor(.green)
                .font(.headline)
        }
        .padding(12)
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ErrorMessage: View {
    let error: String
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text("Error: \(error)")
                .foregroundColor(.red)
                .font(.subheadline)
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ClearButton: View {
    let action: () -> Void
    
    var body: some View {
        Button("Clear Selection", action: action)
            .buttonStyle(.bordered)
    }
}

struct VideoInfo {
    let resolution: CGSize
    let outputSize: CGSize
    let duration: Double
    let frameRate: Double
}

#Preview {
    ContentView()
}
