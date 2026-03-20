import Foundation

/// Throttles calls to the gemini-router Edge function so the app stays under
/// acceptable rates for Gemini and the Edge function. Delay is applied before
/// each invoke and is invisible to the user (no UI change).
///
/// Use by wrapping every gemini-router invoke in `GeminiRouterThrottle.shared.execute { ... }`.
/// This file has no dependency on Supabase; call sites pass their own invoke closure.
actor GeminiRouterThrottle {
    private var lastInvokeTime: Date?
    /// Minimum interval between the start of any two gemini-router invocations.
    private let minInterval: TimeInterval

    static let shared = GeminiRouterThrottle(minInterval: 2.0)

    /// Pacing for trip “magic wand” suggestions: at most one gemini-router call every 5 seconds.
    static let tripSuggestions = GeminiRouterThrottle(minInterval: 5.0)

    init(minInterval: TimeInterval = 2.0) {
        self.minInterval = minInterval
    }

    /// Runs the given operation only after waiting long enough since the last
    /// invocation. Use this to wrap every gemini-router invoke.
    func execute<T>(_ operation: () async throws -> T) async rethrows -> T {
        if let last = lastInvokeTime {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < minInterval {
                let wait = minInterval - elapsed
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
        lastInvokeTime = Date()
        return try await operation()
    }

    /// Runs the given operation with retry/backoff when it fails, primarily
    /// to handle transient 5xx errors (including 503 "Service Unavailable")
    /// from the gemini-router edge function.
    ///
    /// Delays:
    /// - First failure: wait 1 second then retry
    /// - Second failure: wait 2 seconds then retry
    /// - Third failure: wait 5 seconds, then give up if it still fails
    func executeWithRetries<T>(_ operation: () async throws -> T) async throws -> T {
        let backoffDelays: [TimeInterval] = [1, 2, 5]
        var lastError: Error?

        for (attempt, delay) in backoffDelays.enumerated() {
            do {
                // Use the normal throttle for each attempt so we still respect
                // the global pacing between Gemini calls.
                return try await execute(operation)
            } catch {
                lastError = error

                // Only wait and retry if there are remaining attempts.
                if attempt < backoffDelays.count - 1 {
                    // If the error is clearly not transient, we could bail out
                    // early. For now, we conservatively retry on any error
                    // so that 503s and other temporary issues get a chance
                    // to recover before the UI shows a failure.
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
            }
        }

        throw lastError ?? NSError(domain: "GeminiRouterThrottle", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error calling Gemini."])
    }
}
