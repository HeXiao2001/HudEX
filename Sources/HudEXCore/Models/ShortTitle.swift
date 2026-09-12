import Foundation

/// Derives the tiny edge-tab labels.
///
/// The tab is a small bookmark: it may show at most a handful of glyphs, so a
/// long project title must collapse into something stable and recognisable
/// instead of widening the tab or shrinking the font.
public enum ShortTitle {
    /// Maximum glyphs a derived short title may keep.
    public static let maxLength = 4

    /// Sanitises an explicit `短名：` value from the Markdown file.
    public static func sanitizeExplicit(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }

    /// Derives an abbreviation when the file has no `短名：`.
    ///
    /// * `GeoRule` → `GR`   (camel-case initials)
    /// * `Model Training` → `MT` (word initials)
    /// * `alpha-beta` → `AB`
    /// * `博士论文` → `博士`
    /// * `Zotero` → `ZOT`
    public static func derive(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }

        let words = trimmed
            .components(separatedBy: CharacterSet(charactersIn: " \t-_/·、，,。()（）[]【】"))
            .filter { !$0.isEmpty }

        if words.count >= 2 {
            let initials = words.prefix(maxLength).compactMap { $0.first }.map { String($0) }
            let candidate = initials.joined()
            if !candidate.isEmpty { return candidate.uppercased() }
        }

        let word = words.first ?? trimmed

        // Short Latin words are already abbreviations: "PhD" stays "PHD",
        // "OD" stays "OD" instead of losing letters. CJK titles are handled
        // below, where two glyphs carry much more meaning than four letters.
        let isLatin = word.unicodeScalars.allSatisfy { $0.isASCII }
        if isLatin, word.count <= 4, word.allSatisfy({ $0.isLetter }) {
            return word.uppercased()
        }

        // Camel case or acronym: keep the capitalised letters.
        let capitals = word.filter { $0.isUppercase }
        if capitals.count >= 2 {
            return String(capitals.prefix(maxLength))
        }

        // CJK (or any non-Latin script): keep the leading glyphs.
        if word.unicodeScalars.contains(where: { $0.value > 0x2E80 }) {
            return String(word.prefix(2))
        }

        return String(word.prefix(3)).uppercased()
    }

    /// Explicit short title when present, otherwise a derived one.
    public static func resolve(explicit: String?, title: String) -> String {
        if let explicit, let sanitized = sanitizeExplicit(explicit) { return sanitized }
        return derive(from: title)
    }
}

/// Turns headings into stable identifiers, so a reload never re-creates views
/// for projects that merely moved in the file.
public enum StableID {
    public static func slug(_ text: String) -> String {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var scalars: [Character] = []
        var lastWasDash = false
        for character in lowered {
            if character.isLetter || character.isNumber {
                scalars.append(character)
                lastWasDash = false
            } else if !lastWasDash {
                scalars.append("-")
                lastWasDash = true
            }
        }
        var slug = String(scalars)
        while slug.hasPrefix("-") { slug.removeFirst() }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug
    }

    /// Slug plus a numeric suffix for duplicate headings.
    public static func unique(slug base: String, taken: inout Set<String>, fallback: String) -> String {
        var candidate = base.isEmpty ? fallback : base
        var counter = 2
        while taken.contains(candidate) {
            candidate = "\(base.isEmpty ? fallback : base)-\(counter)"
            counter += 1
        }
        taken.insert(candidate)
        return candidate
    }
}
