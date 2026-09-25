import AVFoundation
import SwiftUI
import UIKit

struct ProcessingView: View {
    @EnvironmentObject var appState: AppState

    private let startTime = Date()
    @State private var progress = 0.0
    @State private var task: Task<Void, Never>?
    @State private var showCancelConfirmation = false
    @State private var remainingTimeText = "Estimating time…"
    @State private var lastEstimateUpdate = Date.distantPast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Cancel") {
                showCancelConfirmation = true
            }
            .font(.body)
            .foregroundStyle(Color.accent)
            .frame(height: 44)

            Spacer()

            VStack(spacing: 36) {
                progressRing

                VStack(spacing: 6) {
                    Text("Reframing to \(appState.orientation.displayName.lowercased())")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.textPrimary)

                    Text(remainingTimeText)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Stop processing?", isPresented: $showCancelConfirmation) {
            Button("Keep Processing", role: .cancel) {}
            Button("Stop", role: .destructive) {
                task?.cancel()
                task = nil
                appState.navigationPath.removeLast()
            }
        } message: {
            Text("Your video won't be saved.")
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            guard task == nil else { return }
            task = Task {
                do {
                    try await processVideo()
                    if !Task.isCancelled {
                        await MainActor.run {
                            task = nil
                            appState.navigationPath = NavigationPath([NavigationDestination.completionView])
                        }
                    }
                } catch {
                    task = nil
                    appState.present(error)
                }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            task?.cancel()
            task = nil
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.progressTrack, lineWidth: 8)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: progress)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int((progress * 100).rounded()))")
                    .font(progressNumberFont)
                    .tracking(-1.8)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)

                Text("%")
                    .font(progressPercentSignFont)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(width: 232, height: 232)
    }

    // The progress number is a custom 60pt size, but still needs to respect the
    // user's Dynamic Type setting, so it's scaled relative to `.largeTitle`
    // (and the "%" sign relative to `.title`) rather than using a fixed size.
    private var progressNumberFont: Font {
        Font(UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: .systemFont(ofSize: 60, weight: .medium)))
    }

    private var progressPercentSignFont: Font {
        Font(UIFontMetrics(forTextStyle: .title1).scaledFont(for: .systemFont(ofSize: 28, weight: .regular)))
    }

    private func updateRemainingTime(for progress: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastEstimateUpdate) >= 2 || progress >= 1 else { return }
        lastEstimateUpdate = now

        guard progress >= 0.05 else {
            remainingTimeText = "Estimating time…"
            return
        }

        let elapsed = now.timeIntervalSince(startTime)
        let estimated = elapsed / progress
        let remaining = max(0, estimated - elapsed)

        if remaining < 60 {
            remainingTimeText = "Less than a minute left"
        } else {
            let minutes = Int((remaining / 60).rounded())
            remainingTimeText = "About \(minutes) min left"
        }
    }

    private func processVideo() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        let tmpURL = tempDirectory.appendingPathComponent("pov_\(dateString).MOV")

        try await appState.videoProcessor!.processVideo(
            inputAsset: appState.selectedVideo!.asset,
            outputURL: tmpURL,
            orientation: appState.orientation
        ) { newProgress in
            progress = newProgress
            updateRemainingTime(for: newProgress)
        }

        if Task.isCancelled {
            try? FileManager.default.removeItem(at: tmpURL)
            return
        }

        // TODO: add permissions check / request
        try await LibraryManager.saveVideo(at: tmpURL)

        AudioServicesPlayAlertSoundWithCompletion(1016, nil)
        AudioServicesPlaySystemSoundWithCompletion(kSystemSoundID_Vibrate, nil)

        let outputAsset = AVAsset(url: tmpURL)
        async let thumbnailTask = LibraryManager.thumbnail(for: outputAsset)
        let duration = try await outputAsset.load(.duration)
        let thumbnail = await thumbnailTask

        await MainActor.run {
            appState.outputVideo = OutputVideo(
                url: tmpURL,
                thumbnail: thumbnail,
                duration: duration.seconds,
                orientation: appState.orientation
            )
        }
    }
}

#Preview {
    ProcessingView()
        .environmentObject(AppState())
}
