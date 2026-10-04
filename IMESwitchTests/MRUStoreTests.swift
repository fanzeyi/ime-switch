import Foundation
import Testing

@MainActor
struct MRUStoreTests {
    @Test func promoteMovesToFront() {
        let store = MRUStore(defaults: makeTestDefaults())
        store.reconcile(available: ["a", "b", "c"])
        store.promote("c")
        #expect(store.order == ["c", "a", "b"])
        store.promote("b")
        #expect(store.order == ["b", "c", "a"])
    }

    @Test func promoteAddsUnknownSource() {
        let store = MRUStore(defaults: makeTestDefaults())
        store.reconcile(available: ["a", "b"])
        store.promote("z")
        #expect(store.order == ["z", "a", "b"])
    }

    @Test func reconcileDropsDisabledAndAppendsNew() {
        let store = MRUStore(defaults: makeTestDefaults())
        store.reconcile(available: ["a", "b", "c"])
        store.promote("c")
        store.reconcile(available: ["b", "c", "d"])
        #expect(store.order == ["c", "b", "d"])
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeTestDefaults()
        let first = MRUStore(defaults: defaults)
        first.reconcile(available: ["a", "b", "c"])
        first.promote("b")
        #expect(MRUStore(defaults: defaults).order == ["b", "a", "c"])
    }
}
