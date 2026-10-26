import CryptoKit
import Foundation
import Security

nonisolated enum AuthenticationCodec {
    static func exchangedToken(from data: Data) -> String? {
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }

        if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            if let object = json as? [String: Any] {
                return validatedExchangedToken(
                    object["token"] as? String ?? object["accessToken"] as? String
                )
            }
            if let string = json as? String {
                return validatedExchangedToken(string)
            }
            return nil
        }
        return validatedExchangedToken(raw)
    }

    private static func validatedExchangedToken(_ candidate: String?) -> String? {
        guard let token = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty,
              token.utf8.count <= 8_192
        else {
            return nil
        }
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~+/=")
        )
        guard token.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return token
    }

    static func claims(_ jwt: String) -> (id: String, username: String, avatar: String?)? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1])
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        b64 = b64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard
            let data = Data(base64Encoded: b64),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let id =
            json["http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"] as? String ?? ""
        let name = json["http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"] as? String ?? ""
        let av = (json["urn:discord:avatar"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard !id.isEmpty, !name.isEmpty else { return nil }
        return (id, name, av)
    }

    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func makeChallenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

}
