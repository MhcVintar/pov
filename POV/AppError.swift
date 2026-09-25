import Foundation

enum AppError: Error, LocalizedError {
    case recoverableError(String)
    /// The picked video isn't 4:3 — handled inline on the selection screen rather
    /// than routed to the shared recoverable-error screen, so it's kept distinct
    /// from `recoverableError`.
    case wrongAspectRatio
    case fatalError

    var errorDescription: String? {
        switch self {
        case let .recoverableError(message):
            message
        case .wrongAspectRatio:
            "The video needs to be 4:3. Please choose a different one."
        case .fatalError:
            nil
        }
    }

    static func isRecoverable(_ error: Error) -> Bool {
        guard let appError = error as? AppError else {
            return false
        }

        switch appError {
        case .recoverableError, .wrongAspectRatio:
            return true
        case .fatalError:
            return false
        }
    }
}
