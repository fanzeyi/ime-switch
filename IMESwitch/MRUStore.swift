import Foundation

/// Most-recently-used ordering of input source IDs; index 0 is the current one.
@MainActor
final class MRUStore {
    private static let defaultsKey = "MRUOrder"

    private(set) var order: [String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        order = defaults.stringArray(forKey: Self.defaultsKey) ?? []
    }

    /// The order to cycle through: the current source first, as the starting point even if
    /// it's excluded, then the others that aren't.
    func cycle(excluding excluded: Set<String>) -> [String] {
        order.enumerated().filter { $0.offset == 0 || !excluded.contains($0.element) }.map(\.element)
    }

    func promote(_ id: String) {
        guard order.first != id else { return }
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        save()
    }

    /// Drops sources that are no longer enabled and appends newly enabled ones.
    func reconcile(available: [String]) {
        let set = Set(available)
        var next = order.filter { set.contains($0) }
        for id in available where !next.contains(id) {
            next.append(id)
        }
        if next != order {
            order = next
            save()
        }
    }

    private func save() {
        defaults.set(order, forKey: Self.defaultsKey)
    }
}
