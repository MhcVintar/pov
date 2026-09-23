import Foundation

enum AppError: Error, LocalizedError {
    case recoverableError(String)
    case fatalError

    var errorDescription: String? {
        switch self {
        case let .recoverableError(message):
            message
        case .fatalError:
            nil
        }
    }

    static func isRecoverable(_ error: Error) -> Bool {
        guard let appError = error as? AppError else {
            return false
        }

        if case .recoverableError = appError {
            return true
        }
        return false
    }
}
