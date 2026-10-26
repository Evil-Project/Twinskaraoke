import Foundation

nonisolated enum AccountRepository {
    static func profile(token: String) async throws -> ProfileResponse {
        try await load(ProfileResponse.self, path: "/api/badge/profile", token: token)
    }

    static func uploadLimits(token: String) async throws -> UploadLimits {
        try await load(UploadLimits.self, path: "/api/user/upload-limits", token: token)
    }

    private static func load<Value: Decodable>(_ type: Value.Type, path: String, token: String) async throws -> Value {
        let request = try KaraokeAPIClient.request(path: path, readToken: { token })
        let data = try await KaraokeAPIClient.data(for: request)
        return try JSONDecoder().decode(type, from: data)
    }
}
