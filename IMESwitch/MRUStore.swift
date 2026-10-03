import Foundation

/// Most-recently-used ordering of input source IDs; index 0 is the current one.
@MainActor
final class MRUStore {
    private static let defaultsKey = "MRUOrder"

    private(set) var order: [String]

    init() {
        order = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
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
        UserDefaults.standard.set(order, forKey: Self.defaultsKey)
    }
}
