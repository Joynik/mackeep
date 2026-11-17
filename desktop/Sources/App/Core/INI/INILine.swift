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
        case .empty(let text): text
        case .comment(let text): text
        case .section(_, let text): text
        case .option(let option): option.text
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
        prefix + key + separator
            + value.replacingOccurrences(of: "\n", with: "\n" + prefix + "    ") + comment + suffix
    }

    /// The value of the option, the inline comment included when the
    /// document keeps it.
    func resolvedValue(stripsInlineComments: Bool) -> String {
        (stripsInlineComments ? value : value + comment).trimmingCharacters(
            in: .whitespacesAndNewlines)
    }
}

extension INILine {
    /// The option of the line, when the line holds one.
    var optionValue: INIOption {
        if case .option(let option) = self { return option }
        return INIOption(key: "")
    }
}
