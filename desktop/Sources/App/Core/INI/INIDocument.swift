import Foundation

/// A line of an INI file.
///
/// The lines keep their original text, so a document can be read and written
/// back without any loss: the comments, the order of the sections and the
/// unknown sections are preserved.
enum INILine: Equatable, Sendable {
    /// An empty line, with its original text.
    case empty(String)

    /// A comment, with its original text.
    case comment(String)

    /// A section, with its name.
    case section(name: String, text: String)

    /// An option, with or without a value.
    case option(INIOption)

    /// The original text of the line.
    var text: String {
        switch self {
        case let .empty(text): text
        case let .comment(text): text
        case let .section(_, text): text
        case let .option(option): option.text
        }
    }
}

/// An option of an INI file.
struct INIOption: Equatable, Sendable {
    /// The whitespace before the key.
    var prefix: String = ""

    /// The key of the option.
    var key: String

    /// The text between the key and the value, the delimiter included.
    var separator: String = ""

    /// The value of the option, without the inline comment.
    var value: String = ""

    /// The inline comment, with the whitespace that precedes it.
    var comment: String = ""

    /// The whitespace at the end of the line.
    var suffix: String = ""

    /// Whether the option has a value.
    var hasValue: Bool { !separator.isEmpty }

    /// The original text of the option.
    var text: String {
        prefix + key + separator + value + comment + suffix
    }

    /// The value of the option, the inline comment included when the
    /// document keeps it.
    func resolvedValue(stripsInlineComments: Bool) -> String {
        stripsInlineComments ? value : value + comment
    }
}

extension INILine {
    /// The option of the line, when the line holds one.
    var optionValue: INIOption {
        if case let .option(option) = self { return option }
        return INIOption(key: "")
    }
}

/// A document of an INI file.
///
/// The document is lossless: reading a file and writing it back gives the
/// same file. The values are read the way Python's `configparser` reads
/// them, so Mackeep and the application agree on what a config file holds.
struct INIDocument: Equatable, Sendable {
    /// The lines of the document, in the order they appear.
    private(set) var lines: [INILine] = []

    /// Whether the inline comments are stripped from the values.
    let stripsInlineComments: Bool

    /// Whether the document ends with a newline.
    private(set) var endsWithNewline: Bool = true

    /// Create a document from the text of a file.
    ///
    /// - Parameters:
    ///   - text: The text of the file.
    ///   - stripsInlineComments: Whether the inline comments are stripped
    ///     from the values, the way the main config file of Mackeep does.
    init(text: String, stripsInlineComments: Bool = false) {
        self.stripsInlineComments = stripsInlineComments

        var lines: [INILine] = []
        var content: Substring = Substring(text)
        if content.hasSuffix("\n") {
            content = content.dropLast()
            self.endsWithNewline = true
        } else {
            self.endsWithNewline = false
        }

        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append(INIDocument.parse(String(rawLine)))
        }
        self.lines = lines
    }

    /// Create an empty document.
    init(stripsInlineComments: Bool = false) {
        self.stripsInlineComments = stripsInlineComments
        self.endsWithNewline = true
    }

    // MARK: - Reading

    /// The text of the document.
    var text: String {
        let body: String = lines.map(\.text).joined(separator: "\n")
        return endsWithNewline ? body + "\n" : body
    }

    /// The names of the sections, in the order they appear.
    var sectionNames: [String] {
        lines.compactMap { line in
            if case let .section(name, _) = line { return name }
            return nil
        }
    }

    /// Whether the document has a section.
    ///
    /// - Parameter name: The name of the section.
    /// - Returns: True when the section is there.
    func hasSection(_ name: String) -> Bool {
        sectionNames.contains(name)
    }

    /// The keys of the options of a section, in the order they appear.
    ///
    /// - Parameter section: The name of the section.
    /// - Returns: The keys.
    func optionKeys(inSection section: String) -> [String] {
        var keys: [String] = []
        var current: String?
        for line in lines {
            switch line {
            case let .section(name, _):
                current = name
            case let .option(option):
                if current == section { keys.append(option.key) }
            case .empty(_), .comment:
                continue
            }
        }
        return keys
    }

    /// The value of an option.
    ///
    /// - Parameters:
    ///   - key: The key of the option.
    ///   - section: The name of the section.
    /// - Returns: The value, nil when the option is not there or has no
    ///   value.
    func value(forKey key: String, inSection section: String) -> String? {
        guard let option = option(forKey: key, inSection: section) else {
            return nil
        }
        guard option.hasValue else { return nil }
        return option.resolvedValue(stripsInlineComments: stripsInlineComments)
    }

    /// The values of the options of a section, in the order they appear.
    ///
    /// The options without a value give their key, the way Mackeep stores
    /// the paths of an application.
    ///
    /// - Parameter section: The name of the section.
    /// - Returns: The values.
    func values(inSection section: String) -> [String] {
        var values: [String] = []
        var current: String?
        for line in lines {
            switch line {
            case let .section(name, _):
                current = name
            case let .option(option):
                guard current == section else { continue }
                if option.hasValue {
                    values.append(
                        option.resolvedValue(
                            stripsInlineComments: stripsInlineComments
                        )
                    )
                } else {
                    values.append(option.key)
                }
            case .empty(_), .comment:
                continue
            }
        }
        return values
    }

    /// The option of a section.
    ///
    /// - Parameters:
    ///   - key: The key of the option.
    ///   - section: The name of the section.
    /// - Returns: The option, nil when it is not there.
    func option(forKey key: String, inSection section: String) -> INIOption? {
        var current: String?
        for line in lines {
            switch line {
            case let .section(name, _):
                current = name
            case let .option(option):
                if current == section, option.key == key { return option }
            case .empty(_), .comment:
                continue
            }
        }
        return nil
    }

    // MARK: - Writing

    /// Set the value of an option, adding it when it is not there.
    ///
    /// - Parameters:
    ///   - value: The value of the option.
    ///   - key: The key of the option.
    ///   - section: The name of the section.
    mutating func setValue(_ value: String, forKey key: String, inSection section: String) {
        if let index = indexOfOption(forKey: key, inSection: section) {
            var option = lines[index].optionValue
            option.value = value
            option.comment = ""
            lines[index] = .option(option)
            return
        }
        appendOption(
            INIOption(key: key, separator: " = ", value: value),
            toSection: section
        )
    }

    /// Replace the options of a section with the given keys.
    ///
    /// The options without a value are used, the way Mackeep stores the
    /// paths of an application.
    ///
    /// - Parameters:
    ///   - keys: The keys of the options.
    ///   - section: The name of the section.
    mutating func setOptionKeys(_ keys: [String], inSection section: String) {
        let options: [INIOption] = keys.map { INIOption(key: $0) }
        replaceOptions(options, inSection: section)
    }

    /// Add a section at the end of the document, when it is not there.
    ///
    /// - Parameter name: The name of the section.
    mutating func ensureSection(_ name: String) {
        guard !hasSection(name) else { return }
        let isEmpty: Bool = lines.last.map { $0.text.isEmpty } ?? true
        if !lines.isEmpty, !isEmpty {
            lines.append(.empty(""))
        }
        lines.append(.section(name: name, text: "[\(name)]"))
    }

    /// Remove a section and its options.
    ///
    /// - Parameter name: The name of the section.
    mutating func removeSection(_ name: String) {
        var result: [INILine] = []
        var skipping: Bool = false
        for line in lines {
            switch line {
            case let .section(section, _):
                skipping = section == name
                if !skipping { result.append(line) }
            case .option:
                if !skipping { result.append(line) }
            case .empty(_), .comment:
                if !skipping { result.append(line) }
            }
        }
        lines = result
    }

    // MARK: - Private

    /// The index of an option of a section.
    private func indexOfOption(forKey key: String, inSection section: String) -> Int? {
        var current: String?
        for (index, line) in lines.enumerated() {
            switch line {
            case let .section(name, _):
                current = name
            case let .option(option):
                if current == section, option.key == key { return index }
            case .empty(_), .comment:
                continue
            }
        }
        return nil
    }

    /// The index of the last line of a section.
    private func lastIndexOfSection(_ section: String) -> Int? {
        var last: Int?
        var current: String?
        for (index, line) in lines.enumerated() {
            switch line {
            case let .section(name, _):
                current = name
                if name == section { last = index }
            case .option:
                if current == section { last = index }
            case .empty(_), .comment:
                continue
            }
        }
        return last
    }

    /// Append an option at the end of a section.
    private mutating func appendOption(_ option: INIOption, toSection section: String) {
        ensureSection(section)
        if let last = lastIndexOfSection(section) {
            lines.insert(.option(option), at: last + 1)
        } else {
            lines.append(.option(option))
        }
    }

    /// Replace the options of a section.
    private mutating func replaceOptions(_ options: [INIOption], inSection section: String) {
        // Find the lines of the options of the section
        var indexes: [Int] = []
        var current: String?
        for (index, line) in lines.enumerated() {
            switch line {
            case let .section(name, _):
                current = name
            case .option:
                if current == section { indexes.append(index) }
            case .empty(_), .comment:
                continue
            }
        }

        guard let first = indexes.first else {
            ensureSection(section)
            for option in options { lines.append(.option(option)) }
            return
        }

        // Remove the old options, and put the new ones in their place
        for index in indexes.reversed() {
            lines.remove(at: index)
        }
        for (offset, option) in options.enumerated() {
            lines.insert(.option(option), at: first + offset)
        }
    }

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

        if trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.count >= 2 {
            let name: String = String(trimmed.dropFirst().dropLast())
            return .section(name: name, text: line)
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
        let separator: String = String(rawKey.dropFirst(key.count))
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
                let previous: Character? = value.index(after: index) == value.endIndex
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
