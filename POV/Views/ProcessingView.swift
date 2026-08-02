import AVFoundation
import Photos
import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject var appState: AppState
    
    // TODO: can these not be bindings?
    @Binding var orientation: Orientation
    @Binding var quality: Quality

    private let startTime = Date()
    @State private var progress = 0.0
    @State private var task: Task<Void, Never>?
    
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
                
                Text("Quality: \(quality.displayName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 12)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(
                        Color.blue,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progress)
                
                Text("\(Int(progress * 100))%")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            if progress > 0 {
                Text(estimateRemainingTime())
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
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            guard task == nil else { return }
            task = Task {
                do {
                    try await processVideo()
                    await MainActor.run {
                        task = nil
                        appState.navigationPath = NavigationPath([NavigationDestination.completionView])
                    }
                } catch {
                    appState.error = error
                }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            task?.cancel()
            task = nil
        }
    }
    
    private func estimateRemainingTime() -> String {
        if progress < 0.05 {
            return "Calculating..."
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let estimated = elapsed / progress
        let remaining = estimated - elapsed
        
        if remaining < 60 {
            return String(format: "~%.0f sec remaining", remaining)
        } else {
            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60
            return String(format: "~%d:%02d remaining", minutes, seconds)
        }
    }
    
    private func processVideo() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        let tmpURL = tempDirectory.appendingPathComponent("pov_\(dateString).MOV")
        
        try await appState.videoService!.processVideo(
            inputAsset: appState.asset!,
            outputURL: tmpURL,
            orientation: orientation,
            quality: quality
        ) { newProgress in
                progress = newProgress
        }
        
        if !Task.isCancelled {
            // TODO: add permissions check / request
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tmpURL)
            }
            
            AudioServicesPlayAlertSoundWithCompletion(1016, nil)
            AudioServicesPlaySystemSoundWithCompletion(kSystemSoundID_Vibrate, nil)
        }
        
        try FileManager.default.removeItem(at: tmpURL)
    }
}
