public enum FuzzyMatch {
    public static func matchedIndices(query: String, target: String) -> [Int]? {
        let queryChars = Array(query.lowercased())
        let targetChars = Array(target.lowercased())
        guard !queryChars.isEmpty else { return [] }
        guard !targetChars.isEmpty else { return nil }

        var indices: [Int] = []
        var searchIndex = 0
        for char in queryChars {
            var matched = false
            while searchIndex < targetChars.count {
                if targetChars[searchIndex] == char {
                    matched = true
                    indices.append(searchIndex)
                    searchIndex += 1
                    break
                }
                searchIndex += 1
            }
            guard matched else { return nil }
        }
        return indices
    }

    public static func score(query: String, target: String) -> Int? {
        guard let indices = matchedIndices(query: query, target: target) else { return nil }
        guard !indices.isEmpty else { return 0 }

        var total = 0
        for (i, idx) in indices.enumerated() {
            if i > 0 && idx == indices[i - 1] + 1 {
                total += 6
            } else {
                total += 2
            }
            if idx == 0 { total += 4 }
        }
        return total
    }

    /// Score for pre-lowercased character buffers. Same semantics as
    /// `score(query:target:)` without re-lowercing the target on every call —
    /// the launcher ranks hundreds of items per keystroke.
    public static func score(query: [Character], target: [Character]) -> Int? {
        guard !query.isEmpty else { return 0 }
        guard !target.isEmpty else { return nil }

        var total = 0
        var searchIndex = 0
        var previous = -1
        for char in query {
            var matched = false
            while searchIndex < target.count {
                if target[searchIndex] == char {
                    matched = true
                    total += previous >= 0 && searchIndex == previous + 1 ? 6 : 2
                    if searchIndex == 0 { total += 4 }
                    previous = searchIndex
                    searchIndex += 1
                    break
                }
                searchIndex += 1
            }
            guard matched else { return nil }
        }
        return total
    }

    public static func ranked<T>(_ items: [T], query: String, text: (T) -> String) -> [T] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        return items
            .compactMap { item -> (T, Int)? in
                score(query: query, target: text(item)).map { (item, $0) }
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return text(lhs.0).localizedCaseInsensitiveCompare(text(rhs.0)) == .orderedAscending
            }
            .map(\.0)
    }

    /// A search candidate with its target text preprocessed once, when the
    /// item list is (re)built, instead of once per keystroke.
    public struct Indexed<T> {
        public let item: T
        /// Original search text; used for the alphabetical tie-break.
        public let text: String
        /// Lowercased characters of `text`; the matching surface.
        public let target: [Character]

        public init(item: T, text: String) {
            self.item = item
            self.text = text
            self.target = Array(text.lowercased())
        }
    }

    /// Ranking over precomputed `Indexed` entries. Equivalent ordering to
    /// `ranked(_:query:text:)` but does no per-call string building or
    /// lowercasing, so it is safe to run over large item lists on every
    /// keystroke.
    public static func rankedIndexed<T>(_ indexed: [Indexed<T>], query: String) -> [Indexed<T>] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return indexed }
        let queryChars = Array(query.lowercased())
        return indexed
            .compactMap { entry -> (Indexed<T>, Int)? in
                score(query: queryChars, target: entry.target).map { (entry, $0) }
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.text.localizedCaseInsensitiveCompare(rhs.0.text) == .orderedAscending
            }
            .map(\.0)
    }
}
