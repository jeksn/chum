import Foundation

/// Frequency-weighted recency scoring — Chum's "memory" of what you use.
///
/// A use from `halfLifeDays` ago counts half as much as a use right now, so
/// the score tracks habits, not just history: a command you hammered last
/// month but never touch anymore sinks below one you use weekly.
public enum UsageScore {
    /// Exponential-decay half life, in days.
    public static let halfLifeDays: Double = 7

    /// Rank-bonus scale: decayed score multiplied by this becomes the bonus
    /// added to a fuzzy match score.
    public static let rankBonusScale: Double = 0.5
    /// Cap on the rank bonus, so a well-used item can lift itself above
    /// near-equal fuzzy matches without ever beating a clearly better one.
    public static let maxRankBonus: Double = 5

    /// Decayed usage score for `count` uses, the most recent at `lastUsed`.
    /// Zero when never used.
    public static func score(count: Int, lastUsed: Date?, now: Date = Date()) -> Double {
        guard count > 0, let lastUsed else { return 0 }
        let ageDays = max(0, now.timeIntervalSince(lastUsed)) / 86_400
        return Double(count) * pow(0.5, ageDays / halfLifeDays)
    }

    /// Bonus added on top of a fuzzy match score for ranking. Bounded by
    /// `maxRankBonus` so strong textual matches always win.
    public static func rankBonus(count: Int, lastUsed: Date?, now: Date = Date()) -> Double {
        min(score(count: count, lastUsed: lastUsed, now: now) * rankBonusScale, maxRankBonus)
    }
}
