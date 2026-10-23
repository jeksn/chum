import Foundation

public enum SnippetTemplate {
    public static func resolve(_ text: String, clipboardContent: String = "") -> String {
        var result = text

        result = result.replacingOccurrences(of: "{{clipboard}}", with: clipboardContent)

        result = resolveDates(in: result)

        result = result.replacingOccurrences(of: "{{time}}", with: dateString(offset: 0, format: "HH:mm:ss"))

        return result
    }

    private static func resolveDates(in text: String) -> String {
        let pattern = #"\{\{date\s*(-?\+?\d+)?(?::([^}]+))?\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).reversed()
        var result = text
        for match in matches {
            let fullRange = match.range
            let offsetStr: String
            if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                offsetStr = nsText.substring(with: match.range(at: 1))
            } else {
                offsetStr = "0"
            }
            let fmtStr: String
            if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                fmtStr = nsText.substring(with: match.range(at: 2))
            } else {
                fmtStr = "yyyy-MM-dd"
            }
            let offset = Int(offsetStr) ?? Int(offsetStr.replacingOccurrences(of: "+", with: "")) ?? 0
            let replacement = dateString(offset: offset, format: fmtStr)
            result = (result as NSString).replacingCharacters(in: fullRange, with: replacement)
        }
        return result
    }

    private static func dateString(offset: Int, format: String) -> String {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
