import Foundation

final class Settings: ObservableObject {
    static let shared = Settings()

    private static let key = "homeURL"

    @Published var homeURLString: String {
        didSet {
            UserDefaults.standard.set(homeURLString, forKey: Self.key)
        }
    }

    var homeURL: URL? {
        let trimmed = homeURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }

        return URL(string: "http://\(trimmed)")
    }

    private init() {
        homeURLString = UserDefaults.standard.string(forKey: Self.key) ?? Config.defaultHomeURL
    }

    func reset() {
        homeURLString = Config.defaultHomeURL
    }
}
