import Foundation

/// A case/spacing transformation applied to selected text by the launcher's
/// Text Transformer tool. Pure logic — the launcher captures and replaces
/// the selection; this type only computes the result.
public enum TextTransform: String, CaseIterable, Identifiable, Sendable {
    case uppercase
    case lowercase
    case titleCase
    case sentenceCase
    case camelCase
    case pascalCase
    case snakeCase
    case kebabCase
    case constantCase
    case toggleCase

    public var id: String { rawValue }

    /// The label shown in the transformer list, styled as its own result.
    public var name: String {
        switch self {
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .titleCase: return "Title Case"
        case .sentenceCase: return "Sentence case"
        case .camelCase: return "camelCase"
        case .pascalCase: return "PascalCase"
        case .snakeCase: return "snake_case"
        case .kebabCase: return "kebab-case"
        case .constantCase: return "CONSTANT_CASE"
        case .toggleCase: return "tOGGLE cASE"
        }
    }

    public func apply(to text: String) -> String {
        switch self {
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .titleCase:
            return Self.titleCase(text)
        case .sentenceCase:
            return Self.sentenceCase(text)
        case .camelCase:
            return Self.joinedCase(text, capitalizeFirst: false)
        case .pascalCase:
            return Self.joinedCase(text, capitalizeFirst: true)
        case .snakeCase:
            return Self.words(text).joined(separator: "_")
        case .kebabCase:
            return Self.words(text).joined(separator: "-")
        case .constantCase:
            return Self.words(text).map { $0.uppercased() }.joined(separator: "_")
        case .toggleCase:
            return Self.toggleCase(text)
        }
    }

    /// Capitalizes the first letter of every word in place, preserving all
    /// original separators and whitespace.
    static func titleCase(_ text: String) -> String {
        var result = ""
        var inWord = false
        for character in text {
            if character.isLetter || character.isNumber {
                result += inWord ? String(character).lowercased() : String(character).uppercased()
                inWord = true
            } else {
                result.append(character)
                inWord = false
            }
        }
        return result
    }

    /// Lowercases everything, then capitalizes the first letter of each
    /// sentence (after `.`, `!`, `?`, and newlines).
    static func sentenceCase(_ text: String) -> String {
        var result = ""
        var capitalizeNext = true
        for character in text.lowercased() {
            if capitalizeNext, character.isLetter {
                result += String(character).uppercased()
                capitalizeNext = false
            } else {
                result.append(character)
                if ".!?\n".contains(character) {
                    capitalizeNext = true
                } else if character.isLetter || character.isNumber {
                    capitalizeNext = false
                }
            }
        }
        return result
    }

    /// camelCase / PascalCase: words from any input, joined without
    /// separators, each capitalized except (optionally) the first.
    static func joinedCase(_ text: String, capitalizeFirst: Bool) -> String {
        let words = words(text)
        guard !words.isEmpty else { return "" }
        var result = ""
        for (index, word) in words.enumerated() {
            if index == 0 && !capitalizeFirst {
                result += word
            } else {
                result += word.prefix(1).uppercased() + word.dropFirst()
            }
        }
        return result
    }

    static func toggleCase(_ text: String) -> String {
        return text.map { character -> String in
            if character.isLowercase { return String(character).uppercased() }
            if character.isUppercase { return String(character).lowercased() }
            return String(character)
        }.joined()
    }

    /// Splits text into lowercase words from any input shape: non
    /// alphanumeric characters are separators, and camel/Pascal humps and
    /// acronym boundaries split too (`XMLHttpRequest` → xml, http, request;
    /// `error 404-handled` → error, 404, handled).
    static func words(_ text: String) -> [String] {
        var result: [String] = []
        for chunk in text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let characters = Array(chunk)
            var start = 0
            for index in characters.indices.dropFirst() {
                let previous = characters[index - 1]
                let current = characters[index]
                // lower/digit → Upper starts a new word (camel hump).
                let humpBoundary = current.isUppercase && (previous.isLowercase || previous.isNumber)
                // Upper followed by upper-lower means the acronym ended:
                // the last Upper belongs to the next word (XML|HttpRequest).
                let acronymBoundary = current.isLowercase && previous.isUppercase
                    && index - 2 >= start && characters[index - 2].isUppercase
                if humpBoundary {
                    result.append(String(characters[start..<index]).lowercased())
                    start = index
                } else if acronymBoundary, index - 1 > start {
                    result.append(String(characters[start..<index - 1]).lowercased())
                    start = index - 1
                }
            }
            if start < characters.count {
                result.append(String(characters[start...]).lowercased())
            }
        }
        return result
    }
}
