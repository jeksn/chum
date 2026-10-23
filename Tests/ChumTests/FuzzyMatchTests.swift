import ChumCore

enum FuzzyMatchTests {
    static func runAll(_ t: TestRunner) {
        t.run("FuzzyMatch.subsequenceMatches") {
            t.check(FuzzyMatch.score(query: "lh", target: "Left Half") != nil, "lh should match Left Half")
            t.check(FuzzyMatch.score(query: "mxmz", target: "Maximize") != nil, "mxmz should match Maximize")
        }

        t.run("FuzzyMatch.nonMatchReturnsNil") {
            t.check(FuzzyMatch.score(query: "xz", target: "Left Half") == nil, "xz should not match")
        }

        t.run("FuzzyMatch.emptyQueryScoresZero") {
            t.check(FuzzyMatch.score(query: "", target: "Left Half") == 0, "empty query should score 0")
        }

        t.run("FuzzyMatch.emptyTargetWithQueryReturnsNil") {
            t.check(FuzzyMatch.score(query: "a", target: "") == nil, "empty target should not match")
        }

        t.run("FuzzyMatch.prefixBeatsScattered") {
            let prefix = FuzzyMatch.score(query: "lef", target: "Left Half") ?? 0
            let scattered = FuzzyMatch.score(query: "lf", target: "Left Half") ?? 0
            t.check(prefix > scattered, "prefix \(prefix) should beat scattered \(scattered)")
        }

        t.run("FuzzyMatch.consecutiveBeatsGaps") {
            let consecutive = FuzzyMatch.score(query: "left", target: "Left Half") ?? 0
            let gapped = FuzzyMatch.score(query: "lft", target: "Left Half") ?? 0
            t.check(consecutive > gapped, "consecutive \(consecutive) should beat gapped \(gapped)")
        }

        t.run("FuzzyMatch.rankedPutsBestMatchFirst") {
            let items = ["Maximize", "Half Left", "Left Half"]
            let ranked = FuzzyMatch.ranked(items, query: "left") { $0 }
            t.check(ranked.first == "Left Half", "got \(String(describing: ranked.first))")
        }

        t.run("FuzzyMatch.rankedWithEmptyQueryKeepsOrder") {
            let items = ["A", "B", "C"]
            t.check(FuzzyMatch.ranked(items, query: "") { $0 } == items, "order should be preserved")
        }

        t.run("FuzzyMatch.rankedFiltersNonMatches") {
            let ranked = FuzzyMatch.ranked(["Left Half", "Maximize"], query: "max") { $0 }
            t.check(ranked == ["Maximize"], "got \(ranked)")
        }

        t.run("FuzzyMatch.matchedIndicesSubsequence") {
            let indices = FuzzyMatch.matchedIndices(query: "lh", target: "Left Half")
            t.check(indices == [0, 5], "got \(String(describing: indices))")
        }

        t.run("FuzzyMatch.matchedIndicesConsecutive") {
            let indices = FuzzyMatch.matchedIndices(query: "lef", target: "Left Half")
            t.check(indices == [0, 1, 2], "got \(String(describing: indices))")
        }

        t.run("FuzzyMatch.matchedIndicesEmptyQuery") {
            t.check(FuzzyMatch.matchedIndices(query: "", target: "Left Half") == [], "empty query should return empty")
        }

        t.run("FuzzyMatch.matchedIndicesNonMatchReturnsNil") {
            t.check(FuzzyMatch.matchedIndices(query: "xz", target: "Left Half") == nil, "non-match should return nil")
        }

        t.run("FuzzyMatch.scoreUnchangedAfterRefactor") {
            t.check(FuzzyMatch.score(query: "lh", target: "Left Half") != nil, "lh should still match")
            t.check(FuzzyMatch.score(query: "lef", target: "Left Half")! > FuzzyMatch.score(query: "lf", target: "Left Half")!, "prefix bonus preserved")
        }

        t.run("FuzzyMatch.characterScoreMatchesStringScore") {
            let queries = ["lh", "lef", "lf", "mxmz", "xz", ""]
            let targets = ["Left Half", "Maximize", ""]
            for query in queries {
                for target in targets {
                    let viaString = FuzzyMatch.score(query: query, target: target)
                    let viaChars = FuzzyMatch.score(query: Array(query.lowercased()), target: Array(target.lowercased()))
                    t.check(viaString == viaChars, "score mismatch for \(query) vs \(target): \(String(describing: viaString)) != \(String(describing: viaChars))")
                }
            }
        }

        t.run("FuzzyMatch.indexedRankingMatchesLegacyRanking") {
            let items = ["Left Half", "Maximize", "Half Left", "Safari", "Sublime Text"]
            for query in ["left", "half", "max", "s", "xyzzy", ""] {
                let legacy = FuzzyMatch.ranked(items, query: query) { $0 }
                let indexed = FuzzyMatch.rankedIndexed(items.map { FuzzyMatch.Indexed(item: $0, text: $0) }, query: query).map(\.item)
                t.check(legacy == indexed, "indexed ranking diverged for '\(query)': \(legacy) != \(indexed)")
            }
        }

        t.run("FuzzyMatch.indexedEmptyQueryKeepsOrder") {
            let indexed = ["A", "B", "C"].map { FuzzyMatch.Indexed(item: $0, text: $0) }
            let ranked = FuzzyMatch.rankedIndexed(indexed, query: "").map(\.item)
            t.check(ranked == ["A", "B", "C"], "order should be preserved, got \(ranked)")
        }

        t.run("FuzzyMatch.indexedMatchesCaseInsensitively") {
            let entries = [FuzzyMatch.Indexed(item: "Safari", text: "Safari")]
            t.check(FuzzyMatch.rankedIndexed(entries, query: "SAF").map(\.item) == ["Safari"], "uppercase query should match via precomputed lowercase text")
            t.check(FuzzyMatch.rankedIndexed(entries, query: "saf").map(\.item) == ["Safari"], "lowercase query should match too")
        }
    }
}
