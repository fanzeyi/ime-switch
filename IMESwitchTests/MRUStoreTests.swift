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

    @Test func cycleSkipsExcludedSources() {
        let store = MRUStore(defaults: makeTestDefaults())
        store.reconcile(available: ["a", "b", "c", "d"])
        #expect(store.cycle(excluding: ["b", "d"]) == ["a", "c"])
        #expect(store.cycle(excluding: []) == ["a", "b", "c", "d"])
    }

    @Test func cycleStartsFromExcludedCurrentSource() {
        // Reached by shortcut or from the menu: still the starting point, so a tap goes
        // back to the last included source.
        let store = MRUStore(defaults: makeTestDefaults())
        store.reconcile(available: ["a", "b", "c"])
        store.promote("c")
        #expect(store.cycle(excluding: ["c"]) == ["c", "a", "b"])
        #expect(store.cycle(excluding: ["c", "a"]) == ["c", "b"])
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeTestDefaults()
        let first = MRUStore(defaults: defaults)
        first.reconcile(available: ["a", "b", "c"])
        first.promote("b")
        #expect(MRUStore(defaults: defaults).order == ["b", "a", "c"])
    }
}
