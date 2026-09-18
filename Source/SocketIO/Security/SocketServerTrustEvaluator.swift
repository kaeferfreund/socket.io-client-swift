import Foundation
#if canImport(Security)
import Security

/// Applies additional restrictions, never a trust-all override. Existing
/// URLSession policies are retained and augmented with an explicit hostname.
internal enum SocketServerTrustEvaluator {
    static func evaluate(_ trust: SecTrust, host: String,
                         configuration: SocketTLSConfiguration) -> Bool {
        guard !host.isEmpty, configuration.validationError == nil else { return false }
        var existing: CFArray?
        guard SecTrustCopyPolicies(trust, &existing) == errSecSuccess else { return false }
        var policies = (existing as? [SecPolicy]) ?? []
        policies.append(SecPolicyCreateSSL(true, host as CFString))
        guard SecTrustSetPolicies(trust, policies as CFArray) == errSecSuccess else { return false }
        let pins: [Data]
        switch configuration {
        case .systemDefault: pins = []
        case .certificatePinning(let certificates): pins = certificates
        case .customTrust(let anchors, let certificates):
            let roots = anchors.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
            guard roots.count == anchors.count,
                  SecTrustSetAnchorCertificates(trust, roots as CFArray) == errSecSuccess,
                  SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess else { return false }
            pins = certificates
        }
        guard SecTrustEvaluateWithError(trust, nil) else { return false }
        guard !pins.isEmpty else { return true }
        guard let leaf = Self.leafCertificate(of: trust) else { return false }
        return pins.contains(SecCertificateCopyData(leaf) as Data)
    }

    /// `SecTrustGetCertificateAtIndex` is deprecated from macOS 12 / iOS 15; the
    /// deployment floor is still macOS 10.15 / iOS 13, so both paths remain.
    private static func leafCertificate(of trust: SecTrust) -> SecCertificate? {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            return (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
        }
        return SecTrustGetCertificateAtIndex(trust, 0)
    }
}
#endif
