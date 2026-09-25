import Foundation

extension TimeInterval {
    /// Formats a duration as `m:ss` (e.g. `0:24`, `12:05`), matching the app's duration badges.
    var formattedDuration: String {
        let totalSeconds = Int(self.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
