//
//  ContentView.swift
//  POV
//
//  Created by Miha Vintar on 28. 7. 25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedFilePath: String = "No file selected"
    @State private var showingFilePicker = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("File Picker Demo")
                .font(.title)
                .fontWeight(.bold)
            
            Button("Choose File") {
                openFileDialog()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Selected File Path:")
                    .font(.headline)
                
                ScrollView {
                    Text(selectedFilePath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                .frame(maxHeight: 100)
            }
            
            if selectedFilePath != "No file selected" {
                Button("Clear Selection") {
                    selectedFilePath = "No file selected"
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(30)
        .frame(minWidth: 400, minHeight: 200)
    }
    
    private func openFileDialog() {
        let panel = NSOpenPanel()
        
        // Configure the file dialog
        panel.title = "Choose a file"
        panel.showsHiddenFiles = false
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        // Optional: Set allowed file types
        // panel.allowedContentTypes = [.text, .image, .pdf]
        
        // Show the dialog
        panel.begin { response in
            if response == .OK {
                if let url = panel.url {
                    selectedFilePath = url.path
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
