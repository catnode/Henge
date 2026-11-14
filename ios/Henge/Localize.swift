import Foundation

/// Words the interface shows, in the language the device is set to. SwiftUI looks up what is written
/// straight into a `Text` or a `Button` by itself; this is for everything else: text built from parts,
/// chosen by a condition, or handed to a view as a String. The table is Localizable.strings, keyed by
/// the English, with `%@` wherever a part is filled in at run time.
func L(_ english: String) -> String {
    Translations.shared.translate(english)
}

private final class Translations {
    static let shared = Translations()

    private var exact: [String: String] = [:]
    /// `loose` patterns have few words of their own ("%@ used"), so they only fit text whose parts are short.
    private var patterns: [(regex: NSRegularExpression, format: String, loose: Bool)] = []
    private var cache: [String: String] = [:]
    private let lock = NSLock()

    /// What a format specifier looks like in a key: %@, %lld, %.0f, %1$@ and so on.
    private static let specifier = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?(?:\\.\\d+)?(?:@|d|ld|lld|f|lf)")

    private init() {
        guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings"),
              let table = NSDictionary(contentsOf: url) as? [String: String] else { return }
        for (key, value) in table where key != value {
            let whole = NSRange(key.startIndex..., in: key)
            let found = Self.specifier.matches(in: key, range: whole)
            if found.isEmpty {
                exact[key] = value
                continue
            }
            // The key's fixed words, with each filled-in part captured.
            var pattern = "^"
            var fixed = 0
            var at = key.startIndex
            for match in found {
                guard let range = Range(match.range, in: key) else { continue }
                let words = String(key[at..<range.lowerBound]).replacingOccurrences(of: "%%", with: "%")
                fixed += words.count
                pattern += NSRegularExpression.escapedPattern(for: words) + "(.+?)"
                at = range.upperBound
            }
            let rest = String(key[at...]).replacingOccurrences(of: "%%", with: "%")
            fixed += rest.count
            pattern += NSRegularExpression.escapedPattern(for: rest) + "$"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                patterns.append((regex, value, fixed < 12))
            }
        }
        // Longer patterns first, so the most specific sentence wins.
        patterns.sort { $0.regex.pattern.count > $1.regex.pattern.count }
    }

    func translate(_ english: String) -> String {
        if exact.isEmpty && patterns.isEmpty { return english }
        if let value = exact[english] { return value }
        lock.lock()
        defer { lock.unlock() }
        if let value = cache[english] { return value }
        let value = filled(english) ?? english
        if cache.count > 2000 { cache.removeAll() }
        cache[english] = value
        return value
    }

    /// The translation whose pattern the text fits, with the text's own parts put into it in order.
    private func filled(_ english: String) -> String? {
        let whole = NSRange(english.startIndex..., in: english)
        for (regex, format, loose) in patterns {
            guard let match = regex.firstMatch(in: english, range: whole) else { continue }
            var parts: [String] = []
            var fits = true
            for index in 1..<match.numberOfRanges {
                guard let range = Range(match.range(at: index), in: english) else { parts.append(""); continue }
                let part = String(english[range])
                if loose, part.count > 24 { fits = false }
                parts.append(exact[part] ?? part)
            }
            if !fits { continue }
            var result = ""
            var next = 0
            let formatRange = NSRange(format.startIndex..., in: format)
            var at = format.startIndex
            for found in Self.specifier.matches(in: format, range: formatRange) {
                guard let range = Range(found.range, in: format) else { continue }
                result += format[at..<range.lowerBound].replacingOccurrences(of: "%%", with: "%")
                // %2$@ names its part; a plain %@ takes the next one.
                let text = String(format[range])
                var index = next
                if let dollar = text.firstIndex(of: "$"), let named = Int(text[text.index(after: text.startIndex)..<dollar]) {
                    index = named - 1
                } else {
                    next += 1
                }
                if index >= 0, index < parts.count { result += parts[index] }
                at = range.upperBound
            }
            result += format[at...].replacingOccurrences(of: "%%", with: "%")
            return result
        }
        return nil
    }
}
