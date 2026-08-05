import Foundation

/// Client-side profanity filter for user-generated content (e.g. post comments).
/// Replaces matched words with "###" (whole-word, case-insensitive).
/// Word list is loaded from the bundled ProfanityWords.txt (populated by Scripts/download_profanity_list.sh).
enum ProfanityChecker {
    /// Maximum length for a short comment (one line in the feed).
    static let maxCommentLength = 60

    /// Replacement string for profane words.
    private static let replacement = "###"

    /// Replaces any profane word (whole-word match, case-insensitive) with "###".
    /// Preserves non-matching text and spacing. Uses bundled ProfanityWords.txt if present.
    static func replaceProfanity(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        let words = loadBlockedWords()
        guard !words.isEmpty else { return text }

        var result = text
        // Process by length descending so longer phrases match first (e.g. "mother fucker" before "mother").
        let sorted = words.sorted { $0.count > $1.count }
        for word in sorted {
            guard !word.isEmpty else { continue }
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let nsResult = result as NSString
            let range = NSRange(location: 0, length: nsResult.length)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: replacement
            )
        }
        return result
    }

    /// Loads words from ProfanityWords.txt in the app bundle (one word per line, lowercase).
    /// Returns empty set if file is missing or unreadable.
    private static func loadBlockedWords() -> Set<String> {
        guard let url = Bundle.main.url(forResource: "ProfanityWords", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        let words = content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        return Set(words)
    }
}
