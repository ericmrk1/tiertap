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
}
