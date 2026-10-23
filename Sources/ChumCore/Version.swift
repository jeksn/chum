import Foundation

public enum VersionCompare {
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) > 0
    }

    public static func compare(_ lhs: String, _ rhs: String) -> Int {
        let left = components(lhs)
        let right = components(rhs)

        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return -1 }
            if l > r { return 1 }
        }
        return 0
    }

    private static func components(_ string: String) -> [Int] {
        string
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: ".")
            .map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
    }
}
