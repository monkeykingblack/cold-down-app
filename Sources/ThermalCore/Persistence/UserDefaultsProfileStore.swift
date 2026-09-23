import Foundation

public final class UserDefaultsProfileStore: ProfileStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, key: String = "ColdDown.preferences.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> AppPreferences {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data),
              decoded.schemaVersion == AppPreferences.schemaVersion else {
            return .defaults
        }
        var result = decoded
        result.refreshInterval = min(max(result.refreshInterval, 1), 30)
        result.profiles = result.profiles.mapValues {
            var profile = $0
            profile.thresholdCelsius = min(max(profile.thresholdCelsius, 45), 85)
            return profile
        }
        return result
    }

    public func save(_ preferences: AppPreferences) throws {
        lock.lock(); defer { lock.unlock() }
        let data = try JSONEncoder().encode(preferences)
        defaults.set(data, forKey: key)
    }
}

public actor MemoryProfileStore: ProfileStore {
    public var value: AppPreferences
    public init(_ value: AppPreferences = .defaults) { self.value = value }
    public func load() -> AppPreferences { value }
    public func save(_ preferences: AppPreferences) { value = preferences }
}
