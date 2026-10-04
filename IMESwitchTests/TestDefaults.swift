import Foundation

/// A fresh, empty UserDefaults suite per test, so stores never touch real settings or
/// each other.
func makeTestDefaults(_ name: String = #function) -> UserDefaults {
    let suite = "IMESwitchTests.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
