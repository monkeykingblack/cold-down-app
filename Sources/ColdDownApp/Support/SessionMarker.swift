import Foundation

/// Detects whether the previous run ended cleanly. The flag is set when a session begins and cleared only after
/// a normal quit has returned the fans to Auto; a crash, force quit, or power loss leaves it set.
struct SessionMarker {
    static let key = "ColdDown.sessionActive"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Marks a new session as running and returns true if the previous one never ended cleanly.
    func begin() -> Bool {
        let previousSessionWasUnclean = defaults.bool(forKey: Self.key)
        defaults.set(true, forKey: Self.key)
        return previousSessionWasUnclean
    }

    func end() {
        defaults.set(false, forKey: Self.key)
    }
}
