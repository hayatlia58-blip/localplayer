import Foundation
import Combine

/// 播放进度 / 最近观看，持久化到 UserDefaults
final class ProgressStore: ObservableObject {
    private struct Snapshot: Codable {
        var positions: [String: Double] = [:]
        var totals: [String: Double] = [:]
        var lastPlayed: String?
        var order: [String] = []
    }

    @Published private(set) var positions: [String: Double] = [:]
    @Published private(set) var totals: [String: Double] = [:]
    @Published private(set) var lastPlayed: String?
    @Published private(set) var order: [String] = []

    private let key = "progress.snapshot.v1"
    private let defaults = UserDefaults.standard

    init() { load() }

    func position(for id: String) -> Double { positions[id] ?? 0 }

    func progressFraction(for id: String) -> Double {
        guard let total = totals[id], total > 1 else { return 0 }
        return min(1, max(0, (positions[id] ?? 0) / total))
    }

    func update(id: String, time: Double, total: Double) {
        guard total > 1 else { return }
        // 末尾 15 秒视为看完，清除进度
        if time >= total - 15 {
            positions[id] = nil
            totals[id] = total
        } else if time > 5 {
            positions[id] = time
            totals[id] = total
        }
        lastPlayed = id
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        if order.count > 60 { order = Array(order.prefix(60)) }
        save()
    }

    func clear(id: String) {
        positions[id] = nil
        totals[id] = nil
        order.removeAll { $0 == id }
        if lastPlayed == id { lastPlayed = order.first }
        save()
    }

    /// 最近观看列表中仍然存在的条目
    func recentItems(from items: [VideoItem], limit: Int = 12) -> [VideoItem] {
        let map = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return order.compactMap { map[$0] }.prefix(limit).map { $0 }
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        positions = snap.positions
        totals = snap.totals
        lastPlayed = snap.lastPlayed
        order = snap.order
    }

    private func save() {
        let snap = Snapshot(positions: positions, totals: totals, lastPlayed: lastPlayed, order: order)
        if let data = try? JSONEncoder().encode(snap) {
            defaults.set(data, forKey: key)
        }
    }
}
