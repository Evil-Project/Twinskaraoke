import Foundation

enum AccountDataSection: Hashable {
    case profile
    case uploadLimits
}

enum AccountDataLoadError: Error, Equatable {
    case request
    case transport
    case invalidResponse
    case httpStatus(Int)
    case decoding
}

struct AccountDataLoadResult {
    let profileResponse: ProfileResponse?
    let uploadLimits: UploadLimits?
    let failures: [AccountDataSection: AccountDataLoadError]

    var hasFailures: Bool {
        !failures.isEmpty
    }
}

struct AccountLoadOwnership: Equatable {
    let token: String
    let generation: UInt64

    func isCurrent(token currentToken: String?, generation currentGeneration: UInt64) -> Bool {
        token == currentToken && generation == currentGeneration
    }
}

struct AccountDataLoader {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    private let transport: Transport

    init(
        transport: @escaping Transport = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.transport = transport
    }

    func load(token: String) async -> AccountDataLoadResult {
        async let profileDataResult = fetchData(
            path: "/api/badge/profile",
            token: token
        )
        async let uploadLimitsDataResult = fetchData(
            path: "/api/user/upload-limits",
            token: token
        )

        let (resolvedProfileData, resolvedUploadLimitsData) = await (
            profileDataResult,
            uploadLimitsDataResult
        )
        var failures: [AccountDataSection: AccountDataLoadError] = [:]

        let profileResponse: ProfileResponse?
        switch resolvedProfileData {
        case let .success(data):
            do {
                profileResponse = try JSONDecoder().decode(ProfileResponse.self, from: data)
            } catch {
                profileResponse = nil
                failures[.profile] = .decoding
            }
        case let .failure(error):
            profileResponse = nil
            failures[.profile] = error
        }

        let uploadLimits: UploadLimits?
        switch resolvedUploadLimitsData {
        case let .success(data):
            do {
                uploadLimits = try JSONDecoder().decode(UploadLimits.self, from: data)
            } catch {
                uploadLimits = nil
                failures[.uploadLimits] = .decoding
            }
        case let .failure(error):
            uploadLimits = nil
            failures[.uploadLimits] = error
        }

        return AccountDataLoadResult(
            profileResponse: profileResponse,
            uploadLimits: uploadLimits,
            failures: failures
        )
    }

    private func fetchData(
        path: String,
        token: String
    ) async -> Result<Data, AccountDataLoadError> {
        let request: URLRequest
        do {
            request = try KaraokeAPIClient.request(
                path: path,
                authenticationToken: token,
                guestID: nil
            )
        } catch {
            return .failure(.request)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            return .failure(.transport)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.invalidResponse)
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            return .failure(.httpStatus(httpResponse.statusCode))
        }
        return .success(data)
    }
}
