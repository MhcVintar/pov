import Foundation

enum AppError: Error, LocalizedError {
    case recoverableError(String)
    case fatalError(String)
    
    var errorDescription: String? {
        switch self {
        case let .recoverableError(message):
            message
        case let .fatalError(message):
            message
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
