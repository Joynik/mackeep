import Foundation

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
    private var newline = "\n"

    /// Create a document from the text of a file.
    ///
    /// - Parameters:
    ///   - text: The text of the file.
    ///   - stripsInlineComments: Whether the inline comments are stripped
    ///     from the values, the way the main config file of Mackeep does.
    init(text: String, stripsInlineComments: Bool = false) {
        self.stripsInlineComments = stripsInlineComments

        var lines: [INILine] = []
        self.newline = text.contains("\r\n") ? "\r\n" : "\n"
        var content = Substring(text.replacingOccurrences(of: "\r\n", with: "\n"))
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
        let body = lines.map(\.text).joined(separator: "\n").replacingOccurrences(
            of: "\n", with: newline)
        return endsWithNewline ? body + newline : body
    }

    /// The names of the sections, in the order they appear.
    var sectionNames: [String] {
        lines.compactMap { line in
            if case .section(let name, _) = line { return name }
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

    private func key(of option: INIOption, in section: String) -> String {
        let key = stripsInlineComments ? Self.splitInlineComment(option.key).0 : option.key
        return stripsInlineComments && !["exclude", "xdg_exclude"].contains(section)
            ? key.lowercased() : key
    }

    /// Read indented continuation lines as part of the preceding value.
    private func options(in section: String) -> [INIOption] {
        var result: [INIOption] = []
        var current: String?
        for line in lines {
            switch line {
            case .section(let name, _): current = name
            case .option(let option) where current == section:
                if let last = result.last, last.hasValue, option.prefix.count > last.prefix.count {
                    let text = option.text.trimmingCharacters(in: .whitespaces)
                    let value = stripsInlineComments ? Self.splitInlineComment(text).0 : text
                    result[result.count - 1].value =
                        last.resolvedValue(stripsInlineComments: stripsInlineComments) + "\n"
                        + value
                    result[result.count - 1].comment = ""
                } else {
                    result.append(option)
                }
            default: break
            }
        }
        return result
    }

    func optionKeys(inSection section: String) -> [String] {
        options(in: section).map { key(of: $0, in: section) }
    }

    func value(forKey key: String, inSection section: String) -> String? {
        guard let option = option(forKey: key, inSection: section), option.hasValue else {
            return nil
        }
        return option.resolvedValue(stripsInlineComments: stripsInlineComments)
    }

    func values(inSection section: String) -> [String] {
        options(in: section).map { option in
            option.hasValue
                ? option.resolvedValue(stripsInlineComments: stripsInlineComments)
                : key(of: option, in: section)
        }
    }

    func option(forKey key: String, inSection section: String) -> INIOption? {
        options(in: section).last { self.key(of: $0, in: section) == key }
    }

    /// Structural problems that must be resolved before writing a configuration.
    var diagnostics: [String] {
        var problems: [String] = []
        var sections: Set<String> = []
        var keys: Set<String> = []
        var section: String?
        var previous: INIOption?
        for (offset, line) in lines.enumerated() {
            let location = "Line \(offset + 1)"
            switch line {
            case .section(let name, _):
                if !sections.insert(name).inserted {
                    problems.append("\(location): duplicate section [\(name)]")
                }
                section = name
                previous = nil
                keys = []
            case .option(let option):
                if let previous, option.prefix.count > previous.prefix.count {
                    if !previous.hasValue {
                        problems.append("\(location): continuation after an option without a value")
                    }
                    continue
                }
                previous = option
                if section == nil { problems.append("\(location): option outside a section") }
                if option.key.isEmpty || option.key.hasPrefix("[") {
                    problems.append("\(location): invalid option or section header")
                } else if !keys.insert(key(of: option, in: section ?? "")).inserted {
                    problems.append("\(location): duplicate option \(option.key)")
                }
            case .comment, .empty: break
            }
        }
        return problems
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
            if !option.hasValue { option.separator = " = " }
            option.value = value
            option.comment = ""
            lines[index] = .option(option)
            while hasContinuation(after: index, indentation: option.prefix.count) {
                lines.remove(at: index + 1)
            }
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
            case .section(let section, _):
                skipping = section == name
                if !skipping { result.append(line) }
            case .option:
                if !skipping { result.append(line) }
            case .empty, .comment:
                if !skipping { result.append(line) }
            }
        }
        lines = result
    }

    // MARK: - Private

    private func hasContinuation(after index: Int, indentation: Int) -> Bool {
        guard index + 1 < lines.count, case .option(let option) = lines[index + 1] else {
            return false
        }
        return option.prefix.count > indentation
    }

    /// The index of an option of a section.
    private func indexOfOption(forKey key: String, inSection section: String) -> Int? {
        var current: String?
        for (index, line) in lines.enumerated() {
            switch line {
            case .section(let name, _):
                current = name
            case .option(let option):
                if current == section, self.key(of: option, in: section) == key { return index }
            case .empty, .comment:
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
            case .section(let name, _):
                current = name
                if name == section { last = index }
            case .option:
                if current == section { last = index }
            case .empty, .comment:
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
        let (indexes, header) = optionLocations(in: section)

        guard let first = indexes.first else {
            if let header {
                // The section is there, but it has no option yet, the new
                // ones go right after its header
                for (offset, option) in options.enumerated() {
                    lines.insert(.option(option), at: header + 1 + offset)
                }
                return
            }

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

    /// Locate the existing options and header before replacing a section.
    private func optionLocations(in section: String) -> (indexes: [Int], header: Int?) {
        // Find the lines of the options of the section, and the line of its
        // header
        var indexes: [Int] = []
        var header: Int?
        var current: String?
        for (index, line) in lines.enumerated() {
            switch line {
            case .section(let name, _):
                current = name
                if current == section { header = index }
            case .option:
                if current == section { indexes.append(index) }
            case .empty, .comment:
                continue
            }
        }

        return (indexes, header)
    }

}
