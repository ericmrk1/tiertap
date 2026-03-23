import Foundation
import Supabase

/// Debug logging for `FunctionsClient.invoke` failures (HTTP status, response body, URLError, etc.).
enum FunctionsInvokeLogging {
    static func logVerbose(_ error: Error, context: String) {
        var lines: [String] = []
        lines.append("[TierTap] [functions.invoke] \(context)")
        lines.append("  type: \(String(describing: type(of: error)))")
        lines.append("  localizedDescription: \(error.localizedDescription)")

        if let urlError = error as? URLError {
            lines.append("  URLError.code: \(urlError.code.rawValue) (\(urlError.code))")
            if let s = urlError.failureURLString {
                lines.append("  failureURLString: \(s)")
            }
        }

        if let decoding = error as? DecodingError {
            lines.append("  DecodingError: \(String(describing: decoding))")
        }

        if let fe = error as? FunctionsError {
            switch fe {
            case .relayError:
                lines.append("  FunctionsError.relayError (x-relay-error header)")
            case let .httpError(code, data):
                lines.append("  FunctionsError.httpError HTTP status=\(code)")
                if let body = String(data: data, encoding: .utf8), !body.isEmpty {
                    lines.append("  response body (UTF-8): \(body)")
                } else if data.isEmpty {
                    lines.append("  response body: empty")
                } else {
                    let preview = data.prefix(256).map { String(format: "%02x", $0) }.joined()
                    lines.append("  response body: \(data.count) bytes (non-UTF8), hex prefix: \(preview)")
                }
            }
        } else {
            var nsError: NSError? = error as NSError
            var depth = 0
            while let e = nsError, depth < 6 {
                lines.append("  NSError[\(depth)] domain=\(e.domain) code=\(e.code) description=\(e.localizedDescription)")
                if !e.userInfo.isEmpty {
                    let info = e.userInfo.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
                    lines.append("  userInfo: \(info)")
                }
                nsError = e.userInfo[NSUnderlyingErrorKey] as? NSError
                depth += 1
            }
        }

        print(lines.joined(separator: "\n"))
    }
}
