import Foundation

/// Places in a shared list (slides, a slide's objects, themes, a theme's layouts) as keys that sort: each item has a
/// key of its own, and the list is its items sorted by key (then by identifier, where two keys are the same).
///
/// Moving an item gives it a new key between its new neighbors' keys, and adding one gives it a key of its own, so
/// two people moving and adding different items at the same time change different keys, and every item each of them
/// moved or added keeps its place on every Mac. Keys are fractions written in base 62 ("V" is a half), compared as
/// text; there's always another key between two different keys.
public enum OrderKeys {
    static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    static let base = digits.count
    private static let values: [Character: Int] = Dictionary(uniqueKeysWithValues: digits.enumerated().map { ($1, $0) })

    private static func number(_ key: String) -> [Int] { key.map { values[$0] ?? 0 } }
    private static func text(_ number: [Int]) -> String { String(number.map { digits[$0] }) }

    /// A key that sorts after `lower` and before `upper`; nil for either means the start or the end. `lower` must sort
    /// before `upper`.
    public static func between(_ lower: String?, _ upper: String?) -> String {
        let a = number(lower ?? "")
        let b = upper.map(number)
        var result: [Int] = []
        var index = 0
        // Copy the digits the two keys share.
        while true {
            let low = index < a.count ? a[index] : 0
            let high = b.map { index < $0.count ? $0[index] : 0 } ?? base
            if low == high {
                result.append(low)
                index += 1
                continue
            }
            if high - low > 1 {
                result.append((low + high) / 2)
                return text(result)
            }
            // Next to each other: keep the lower digit, then go above the rest of the lower key.
            result.append(low)
            index += 1
            while true {
                let digit = index < a.count ? a[index] : 0
                if digit < base - 1 {
                    result.append((digit + base) / 2)
                    return text(result)
                }
                result.append(digit)
                index += 1
            }
        }
    }

    /// `count` keys in order, spread evenly, for a list starting out.
    public static func spread(_ count: Int) -> [String] {
        guard count > 0 else { return [] }
        var length = 1
        var capacity = base
        while capacity < count * 4 {
            length += 1
            capacity *= base
        }
        let step = capacity / (count + 1)
        return (1...count).map { position in
            var value = step * position
            var number = [Int](repeating: 0, count: length)
            for place in stride(from: length - 1, through: 0, by: -1) {
                number[place] = value % base
                value /= base
            }
            // Keys never end in a zero, which would make two ways to write one place.
            if number.last == 0 { number[number.count - 1] = 1 }
            return text(number)
        }
    }

    /// New keys for the items of `order` that need them, so that sorting every item by its key gives `order`: those
    /// added, and as few moved ones as possible. `keys` are the items' keys as they are.
    public static func assign<ID: Hashable>(_ order: [ID], keys: [ID: String], tieBreak: (ID) -> String) -> [ID: String] {
        // The longest run of items, in their new order, whose keys already sort that way keeps its keys.
        var kept = Set(longestSortedRun(order, keys: keys, tieBreak: tieBreak))
        var result: [ID: String] = [:]
        var index = 0
        while index < order.count {
            if kept.contains(order[index]) {
                index += 1
                continue
            }
            // A run of items needing keys, between the kept items around it.
            var end = index
            while end < order.count, !kept.contains(order[end]) { end += 1 }
            let lower = index > 0 ? (result[order[index - 1]] ?? keys[order[index - 1]]) : nil
            var upper = end < order.count ? keys[order[end]] : nil
            // Two keys the same leave no room between them: the one after takes a new key too.
            if let lower, let current = upper, current <= lower {
                kept.remove(order[end])
                upper = nil
                continue
            }
            for (position, key) in zip(index..<end, Self.keys(end - index, between: lower, upper)) { result[order[position]] = key }
            index = end
        }
        return result
    }

    /// `count` keys in order between `lower` and `upper`, halving the gap each time so that many of them stay short.
    public static func keys(_ count: Int, between lower: String?, _ upper: String?) -> [String] {
        guard count > 0 else { return [] }
        let middle = between(lower, upper)
        let before = (count - 1) / 2
        return keys(before, between: lower, middle) + [middle] + keys(count - 1 - before, between: middle, upper)
    }

    /// The items keeping their keys: the longest subsequence of `order` already sorted by key (and identifier).
    private static func longestSortedRun<ID: Hashable>(_ order: [ID], keys: [ID: String], tieBreak: (ID) -> String) -> [ID] {
        let candidates = order.compactMap { id in keys[id].map { (id: id, key: $0, tie: tieBreak(id)) } }
        guard !candidates.isEmpty else { return [] }
        func before(_ a: (id: ID, key: String, tie: String), _ b: (id: ID, key: String, tie: String)) -> Bool {
            a.key != b.key ? a.key < b.key : a.tie < b.tie
        }
        // Patience sorting: tails[length] is the index of the smallest last item of a run of length + 1.
        var tails: [Int] = []
        var previous = [Int](repeating: -1, count: candidates.count)
        for index in candidates.indices {
            var low = 0
            var high = tails.count
            while low < high {
                let middle = (low + high) / 2
                if before(candidates[tails[middle]], candidates[index]) { low = middle + 1 } else { high = middle }
            }
            if low > 0 { previous[index] = tails[low - 1] }
            if low == tails.count { tails.append(index) } else { tails[low] = index }
        }
        var run: [ID] = []
        var index = tails.last ?? -1
        while index >= 0 {
            run.append(candidates[index].id)
            index = previous[index]
        }
        return run.reversed()
    }

    /// Items sorted as a shared list sorts them.
    public static func sorted<ID>(_ items: [(id: ID, key: String)], tieBreak: (ID) -> String) -> [ID] {
        items.sorted { a, b in a.key != b.key ? a.key < b.key : tieBreak(a.id) < tieBreak(b.id) }.map(\.id)
    }
}
