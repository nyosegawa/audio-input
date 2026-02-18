import Foundation

enum RetryHelper {
    static func withRetry<T: Sendable>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                if !isRetryable(error) || attempt == maxAttempts - 1 {
                    throw error
                }
                let delay = initialDelay * pow(2.0, Double(attempt))
                try await Task.sleep(for: .seconds(delay))
            }
        }
        throw lastError!
    }

    private static func isRetryable(_ error: Error) -> Bool {
        // Network errors (timeout, connection lost, etc.)
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotConnectToHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        // Transcription API errors
        if case .apiError(let msg) = error as? TranscriptionError {
            return msg.contains("HTTP 429") || msg.contains("HTTP 5")
        }
        if case .networkError = error as? TranscriptionError {
            return true
        }
        // Text processing errors (OpenRouter)
        if let tpError = error as? TextProcessingError {
            return tpError.isRetryable
        }
        return false
    }
}
