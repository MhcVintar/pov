//
//  ContentView.swift
//  POV
//
//  Created by Miha Vintar on 28. 7. 25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedFilePath: String = "No file selected"
    @State private var selectedVideoURL: URL?
    @State private var isProcessing = false
    @State private var processingComplete = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("GPUImage3 Video Gaussian Filter")
                .font(.title)
                .fontWeight(.bold)
            
            Button("Choose Video File") {
                openFileDialog()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            if selectedFilePath != "No file selected" {
                VStack(alignment: .leading, spacing: 8) {
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
                
                Button(isProcessing ? "Processing..." : "Process & Save Video") {
                    processAndSaveVideo()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedVideoURL == nil || isProcessing)
                
                if processingComplete {
                    Text("✓ Video processed and saved successfully!")
                        .foregroundColor(.green)
                        .font(.headline)
                }
                
                Button("Clear Selection") {
                    clearSelection()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(30)
        .frame(minWidth: 400, minHeight: 250)
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
                    processingComplete = false // Reset completion state
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
        savePanel.nameFieldStringValue = "processed.mov"
        
        savePanel.begin { response in
            guard response == .OK, let outputURL = savePanel.url else { return }
            
            self.isProcessing = true
            self.processingComplete = false
            
            DispatchQueue.global(qos: .userInitiated).async {
                self.processVideo(inputURL: inputVideoURL, outputURL: outputURL)
            }
        }
    }
    
    private func processVideo(inputURL: URL, outputURL: URL) {
        let converterController = VideoConverterViewController()
        converterController.setupConverter()
        
        Task {
            await converterController.convertVideo(inputPath: inputURL.path, outputPath: outputURL.path)
            DispatchQueue.main.async {
                self.isProcessing = false
                self.processingComplete = true
            }
        }
    }
    
    private func clearSelection() {
        selectedFilePath = "No file selected"
        selectedVideoURL = nil
        processingComplete = false
    }
}

#Preview {
    ContentView()
}
