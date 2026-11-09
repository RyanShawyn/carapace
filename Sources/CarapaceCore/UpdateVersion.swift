import Foundation

/// 版本号比较：按数字段逐段比较，忽略 `v` 前缀和预发布后缀。
public enum UpdateVersion {
    public static func compare(_ lhs: String, _ rhs: String) -> Int {
        let left = components(lhs)
        let right = components(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? -1 : 1 }
        }
        return 0
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) > 0
    }

    private static func components(_ raw: String) -> [Int] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        // 只比较数字主干：1.2.3-beta.1 → 1.2.3
        let main = text.split(separator: "-", maxSplits: 1).first.map(String.init) ?? text
        return main.split(separator: ".").map { Int($0) ?? 0 }
    }
}