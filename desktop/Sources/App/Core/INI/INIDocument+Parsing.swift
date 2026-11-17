import Foundation

extension INIDocument {
    /// Parse a line of a file.
    ///
    /// - Parameter line: The line.
    /// - Returns: The parsed line.
    static func parse(_ line: String) -> INILine {
        let trimmed: String = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .empty(line) }

        if trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
            return .comment(line)
        }

        if trimmed.hasPrefix("["), let end = trimmed.firstIndex(of: "]") {
            if end > trimmed.index(after: trimmed.startIndex) {
                let name = String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
                return .section(name: name, text: line)
            }
        }

        return .option(INIDocument.parseOption(line))
    }

    /// Parse the option of a line.
    ///
    /// - Parameter line: The line.
    /// - Returns: The option.
    static func parseOption(_ line: String) -> INIOption {
        let prefix: String = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        var rest: Substring = line.dropFirst(prefix.count)
        let suffix: String = String(
            rest.reversed().prefix(while: { $0 == " " || $0 == "\t" }).reversed()
        )
        if !suffix.isEmpty { rest = rest.dropLast(suffix.count) }

        // The key ends at the first delimiter
        guard let delimiterIndex = rest.firstIndex(where: { $0 == "=" || $0 == ":" }) else {
            return INIOption(prefix: prefix, key: String(rest), suffix: suffix)
        }

        let rawKey: String = String(rest[..<delimiterIndex])
        let key: String = rawKey.trimmingCharacters(in: .whitespaces)
        let afterKey: Substring = rest[rest.index(after: delimiterIndex)...]
        let spaces: String = String(
            afterKey.prefix(while: { $0 == " " || $0 == "\t" })
        )
        let rawValue: String = String(afterKey.dropFirst(spaces.count))
        // The separator keeps the whitespace around the delimiter
        let separator: String =
            String(rawKey.dropFirst(key.count))
            + String(rest[delimiterIndex])
            + spaces

        // The inline comment, when there is one
        let (value, comment): (String, String) = INIDocument.splitInlineComment(rawValue)

        return INIOption(
            prefix: prefix,
            key: key,
            separator: separator,
            value: value,
            comment: comment,
            suffix: suffix
        )
    }

    /// Split the inline comment of a value.
    ///
    /// The comment starts at the beginning of the line or after a
    /// whitespace, the way Python's `configparser` finds it.
    ///
    /// - Parameter value: The value.
    /// - Returns: The value and the comment.
    static func splitInlineComment(_ value: String) -> (String, String) {
        var index: String.Index = value.startIndex
        while index < value.endIndex {
            let character: Character = value[index]
            if character == ";" || character == "#" {
                let previous: Character? =
                    index == value.startIndex
                    ? nil
                    : value[value.index(before: index)]
                if index == value.startIndex || previous == " " || previous == "\t" {
                    // The whitespace before the comment belongs to it
                    var start: String.Index = index
                    while start > value.startIndex {
                        let before: Character = value[value.index(before: start)]
                        if before != " " && before != "\t" { break }
                        start = value.index(before: start)
                    }
                    let comment: String = String(value[start...])
                    let head: String = String(value[..<start])
                    return (head.trimmingCharacters(in: .whitespaces), comment)
                }
            }
            index = value.index(after: index)
        }
        return (value, "")
    }
}
