import Foundation
import ChumCore

enum UsageScoreTests {
    static func runAll(_ t: TestRunner) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        t.run("UsageScore.neverUsedIsZero") {
            t.check(UsageScore.score(count: 0, lastUsed: now, now: now) == 0, "zero count should score 0")
            t.check(UsageScore.score(count: 5, lastUsed: nil, now: now) == 0, "missing lastUsed should score 0")
        }

        t.run("UsageScore.freshUseScoresFullCount") {
            let s = UsageScore.score(count: 4, lastUsed: now, now: now)
            t.check(abs(s - 4) < 1e-9, "a use right now should count fully, got \(s)")
        }

        t.run("UsageScore.decaysWithHalfLife") {
            let oneHalfLife = Calendar.current.date(byAdding: .day, value: -Int(UsageScore.halfLifeDays), to: now)!
            let s = UsageScore.score(count: 4, lastUsed: oneHalfLife, now: now)
            t.check(abs(s - 2) < 1e-6, "one half life should halve the score, got \(s)")
            let twoHalfLives = Calendar.current.date(byAdding: .day, value: -2 * Int(UsageScore.halfLifeDays), to: now)!
            let s2 = UsageScore.score(count: 4, lastUsed: twoHalfLives, now: now)
            t.check(abs(s2 - 1) < 1e-6, "two half lives should quarter the score, got \(s2)")
        }

        t.run("UsageScore.futureLastUsedClampsToFull") {
            let future = now.addingTimeInterval(3600)
            let s = UsageScore.score(count: 3, lastUsed: future, now: now)
            t.check(abs(s - 3) < 1e-9, "future lastUsed should not inflate the score, got \(s)")
        }

        t.run("UsageScore.moreUsesBeatFewer") {
            let recent = UsageScore.score(count: 10, lastUsed: now, now: now)
            let old = UsageScore.score(count: 3, lastUsed: now.addingTimeInterval(-30 * 86_400), now: now)
            t.check(recent > old, "10 fresh uses (\(recent)) should beat 3 uses a month old (\(old))")
        }

        t.run("UsageScore.rankBonusIsCapped") {
            let huge = UsageScore.rankBonus(count: 10_000, lastUsed: now, now: now)
            t.check(huge == UsageScore.maxRankBonus, "bonus should cap at \(UsageScore.maxRankBonus), got \(huge)")
            let zero = UsageScore.rankBonus(count: 0, lastUsed: nil, now: now)
            t.check(zero == 0, "never used should give no bonus, got \(zero)")
        }

        t.run("FuzzyMatch.rankedIndexedBonusLiftsEqualScores") {
            let a = FuzzyMatch.Indexed(item: "a", text: "Alpha")
            let b = FuzzyMatch.Indexed(item: "b", text: "Alphabet")
            // Same fuzzy score for "alp"; b carries a usage bonus.
            let ranked = FuzzyMatch.rankedIndexed([a, b], query: "alp") { $0 == "b" ? 3 : 0 }
            t.check(ranked.first?.item == "b", "the bonus item should rank first on an equal fuzzy score, got \(ranked.map(\.item))")
        }

        t.run("FuzzyMatch.rankedIndexedBonusDoesNotBeatBetterMatch") {
            // "Alp" scores 22 for query "alp"; the scattered "a l p" scores 10,
            // so even the max bonus (5) keeps the better match on top.
            let weak = FuzzyMatch.Indexed(item: "weak", text: "a l p")
            let strong = FuzzyMatch.Indexed(item: "strong", text: "Alp")
            let ranked = FuzzyMatch.rankedIndexed([weak, strong], query: "alp") { $0 == "weak" ? UsageScore.maxRankBonus : 0 }
            t.check(ranked.first?.item == "strong", "a clearly better fuzzy match must stay on top, got \(ranked.map(\.item))")
        }

        t.run("FuzzyMatch.rankedIndexedWithoutBonusUnchanged") {
            let a = FuzzyMatch.Indexed(item: "a", text: "Left Half")
            let b = FuzzyMatch.Indexed(item: "b", text: "Left")
            let ranked = FuzzyMatch.rankedIndexed([a, b], query: "left")
            t.check(ranked.first?.item == "b", "without bonus the tighter match wins, got \(ranked.map(\.item))")
        }
    }
}
