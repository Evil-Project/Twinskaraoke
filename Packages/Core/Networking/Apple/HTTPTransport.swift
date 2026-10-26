import Foundation

nonisolated enum HTTPTransport {
  enum APIError: Error {
    case invalidURL
    case invalidBody
    case invalidResponse
    case httpStatus(Int)
    case decodeFailed
  }

  static func data(
    for request: URLRequest,
    retriesNonIdempotentRequest: Bool = false,
    allowsRetry: Bool = true,
    send: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) },
    readToken: @Sendable () -> String? = { CredentialStore.token }
  ) async throws -> Data {
    let maxRetries = 3
    let baseDelay: Duration = .milliseconds(500)
    let canRetry = allowsRetry && (retriesNonIdempotentRequest || isIdempotent(request))

    for attempt in 0..<maxRetries {
      do {
        let (data, response) = try await send(request)
        guard let httpResponse = response as? HTTPURLResponse else {
          throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
          if httpResponse.statusCode == 401,
            let authorization = request.value(forHTTPHeaderField: "Authorization"),
            let currentToken = readToken(),
            authorization == "Bearer \(currentToken)"
          {
            NotificationCenter.default.post(name: .karaokeSessionExpired, object: nil,
                                            userInfo: ["requestToken": currentToken])
          }

          if canRetry && shouldRetry(statusCode: httpResponse.statusCode) && attempt < maxRetries - 1 {
            let delay: Duration
            if httpResponse.statusCode == 429,
              let retryAfter = retryAfterInterval(from: httpResponse)
            {
              delay = .seconds(retryAfter)
            } else {
              delay = backoffDelay(attempt: attempt, baseDelay: baseDelay)
            }
            try await Task.sleep(for: delay)
            continue
          }
          throw APIError.httpStatus(httpResponse.statusCode)
        }
        return data
      } catch let error as URLError {

        if canRetry && shouldRetry(urlError: error) && attempt < maxRetries - 1 {
          try await Task.sleep(for: backoffDelay(attempt: attempt, baseDelay: baseDelay))
          continue
        }
        throw error
      } catch {

        throw error
      }
    }

    throw APIError.invalidResponse
  }

  private static func isIdempotent(_ request: URLRequest) -> Bool {
    guard let method = request.httpMethod?.uppercased() else { return true }
    return method == "GET" || method == "HEAD" || method == "PUT" || method == "DELETE"
  }
  private static func backoffDelay(attempt: Int, baseDelay: Duration) -> Duration {
    baseDelay * Double(1 << attempt) + baseDelay * Double.random(in: 0 ... 0.5)
  }
  private static let maxRetryAfterInterval: TimeInterval = 300

  private static func retryAfterInterval(from response: HTTPURLResponse) -> TimeInterval? {
    guard let value = response.value(forHTTPHeaderField: "Retry-After")?
      .trimmingCharacters(in: .whitespaces)
    else { return nil }
    if let seconds = TimeInterval(value), seconds >= 0 {
      return min(seconds, maxRetryAfterInterval)
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    guard let date = formatter.date(from: value) else { return nil }
    return min(max(0, date.timeIntervalSinceNow), maxRetryAfterInterval)
  }

  private static func shouldRetry(statusCode: Int) -> Bool {

    return statusCode == 408 ||
           statusCode == 429 ||
           ((500..<600).contains(statusCode) && statusCode != 501)
  }

  private static func shouldRetry(urlError: URLError) -> Bool {

    switch urlError.code {
    case .timedOut,
         .cannotConnectToHost,
         .networkConnectionLost,
         .resourceUnavailable,
         .badServerResponse:
      return true
    default:
      return false
    }
  }

}
