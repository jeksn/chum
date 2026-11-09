import Foundation

/// Pure text-edit math for snippet expansion: where the typed keyword sits
/// in the focused text field, and what the field should look like after the
/// expansion. All offsets are UTF-16 (NSString/CFRange), matching what
/// Accessibility reports and expects.
public enum SnippetTextEdit {

    /// The range the typed keyword occupies at the caret, plus any selected
    /// suffix that must be replaced with it.
    ///
    /// Two shapes, depending on where the selection is:
    /// - Normal fields: empty selection at the caret — the keyword ends at
    ///   the caret (`selectionStart == selectionLength == 0` offset-wise).
    /// - Omnibox-style fields (Chrome/Safari address bar): the inline
    ///   autocomplete suggestion is a live selection right AFTER the typed
    ///   text, so the keyword ends at the selection START and the range must
    ///   also cover the suggestion, or it would survive the expansion.
    ///
    /// Returns nil when the value doesn't have the keyword at either spot
    /// (e.g. the app hasn't processed the final keystroke yet, or the
    /// expansion already landed).
    public static func replacementRange(value: String,
                                        selectionStart: Int,
                                        selectionLength: Int,
                                        keyword: String) -> NSRange? {
        let nsValue = value as NSString
        let keywordLength = (keyword as NSString).length
        guard keywordLength > 0, keywordLength <= nsValue.length else { return nil }
        let caret = selectionStart + selectionLength

        if selectionStart >= keywordLength,
           nsValue.substring(with: NSRange(location: selectionStart - keywordLength, length: keywordLength)) == keyword {
            return NSRange(location: selectionStart - keywordLength, length: keywordLength + selectionLength)
        }
        if caret >= keywordLength,
           nsValue.substring(with: NSRange(location: caret - keywordLength, length: keywordLength)) == keyword {
            return NSRange(location: caret - keywordLength, length: keywordLength)
        }
        return nil
    }

    /// The value with the keyword range replaced by the expansion.
    public static func replacedValue(value: String,
                                     range: NSRange,
                                     expansion: String) -> String {
        (value as NSString).replacingCharacters(in: range, with: expansion)
    }

    /// The caret position right after the inserted expansion.
    public static func caretAfterExpansion(in range: NSRange, expansion: String) -> Int {
        range.location + (expansion as NSString).length
    }

    /// Whether `current` shows a successful application of the edit: either
    /// the exact expected value, or the expansion present where it was
    /// inserted (some apps normalize the value on set — trailing newline
    /// etc. — so exact equality alone would misread a success as a failure
    /// and risk a double insert on the fallback path).
    public static func isApplied(current: String, expected: String, insertLocation: Int, expansion: String) -> Bool {
        let nsCurrent = current as NSString
        if nsCurrent == (expected as NSString) { return true }
        if insertLocation <= nsCurrent.length,
           nsCurrent.substring(from: insertLocation).hasPrefix(expansion) {
            return true
        }
        return false
    }
}
