import Foundation

enum MirrorConfiguration {
    static let userDefaultsKey = "mirrorBaseURL"
    static let defaultBaseURL = "https://mirror-production-a23c.up.railway.app"

    static func currentBaseURL(defaults: UserDefaults = .standard) -> String {
        let value = defaults.string(forKey: userDefaultsKey) ?? defaultBaseURL
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultBaseURL : value
    }

    static func normalizedBaseURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw MirrorConfigurationError.invalidURL
        }

        let isLoopback = ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
        #if DEBUG
        guard scheme == "https" || (scheme == "http" && isLoopback) else {
            throw MirrorConfigurationError.requiresHTTPS
        }
        #else
        guard scheme == "https" else {
            throw MirrorConfigurationError.requiresHTTPS
        }
        #endif

        components.scheme = scheme
        if components.path == "/" { components.path = "" }
        while components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let url = components.url else { throw MirrorConfigurationError.invalidURL }
        return url
    }

    static func save(_ rawValue: String, defaults: UserDefaults = .standard) throws -> URL {
        let url = try normalizedBaseURL(from: rawValue)
        defaults.set(url.absoluteString, forKey: userDefaultsKey)
        return url
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
    }

    static func checkConnection(to baseURL: URL, session: URLSession = .shared) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["ok"] as? Bool == true else {
            throw MirrorConfigurationError.incompatibleServer
        }
    }
}

enum MirrorConfigurationError: Error, LocalizedError, Equatable {
    case invalidURL
    case requiresHTTPS
    case incompatibleServer

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a complete server address, such as https://anky.example.com."
        case .requiresHTTPS:
            return "A custom server must use HTTPS. Localhost HTTP is available in development builds."
        case .incompatibleServer:
            return "That server did not answer as an Anky server."
        }
    }
}

/// The birth date is private profile material. It remains in the device-only
/// keychain; network requests receive only the derived age in whole years.
struct WriterProfileStore {
    private static let birthDateAccount = "writer.profile.birth-date.v1"
    private let keychain: KeychainClient
    private let calendar: Calendar

    init(keychain: KeychainClient = KeychainClient(), calendar: Calendar = .current) {
        self.keychain = keychain
        self.calendar = calendar
    }

    func birthDate() -> Date? {
        guard let data = try? keychain.data(for: Self.birthDateAccount),
              let string = String(data: data, encoding: .utf8) else { return nil }
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) }
    }

    func saveBirthDate(_ date: Date) throws {
        let normalized = calendar.startOfDay(for: date)
        guard normalized <= calendar.startOfDay(for: Date()),
              let age = ageYears(on: Date(), birthDate: normalized),
              age <= 120 else {
            throw WriterProfileError.invalidBirthDate
        }
        let components = calendar.dateComponents([.year, .month, .day], from: normalized)
        guard let year = components.year, let month = components.month, let day = components.day else {
            throw WriterProfileError.invalidBirthDate
        }
        let dateOnly = String(format: "%04d-%02d-%02d", year, month, day)
        try keychain.save(Data(dateOnly.utf8), account: Self.birthDateAccount)
    }

    func clear() throws {
        try keychain.delete(account: Self.birthDateAccount)
    }

    func ageYears(on date: Date = Date(), birthDate: Date? = nil) -> Int? {
        guard let birthDate = birthDate ?? self.birthDate() else { return nil }
        let years = calendar.dateComponents([.year], from: birthDate, to: date).year
        guard let years, (0...120).contains(years) else { return nil }
        return years
    }
}

enum WriterProfileError: Error, LocalizedError {
    case invalidBirthDate

    var errorDescription: String? {
        "Choose a valid birth date."
    }
}
