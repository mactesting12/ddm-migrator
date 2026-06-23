import Foundation
import Security

/// Stage 2a — recover the raw profile plist from an input file.
///
/// Jamf (and several other MDMs) export `.mobileconfig` files wrapped in a
/// CMS/PKCS7 signature envelope; the bytes on disk are DER, not a plist. We:
///
///   1. Detect whether the input already parses as a property list. If so it
///      was never signed — pass it straight through.
///   2. Otherwise treat it as a CMS message and use the Security framework's
///      `CMSDecoder` to strip the envelope and recover the inner content,
///      then confirm that content is a plist.
///
/// We deliberately use the native `CMSDecoder` API rather than shelling out to
/// `openssl smime -verify -noverify`: no external process, no PATH assumptions,
/// works in a sandboxed/notarized app, and never blocks on certificate trust
/// (we only need the *content*, not signature validation — this is a
/// transformation tool, not a trust gate).
public enum ProfileDecoder {

    public enum DecodeError: Error, LocalizedError, Equatable {
        case empty
        case cmsDecodeFailed(OSStatus)
        case notAProfile

        public var errorDescription: String? {
            switch self {
            case .empty:
                return "File is empty."
            case .cmsDecodeFailed(let status):
                return "Could not strip the CMS/PKCS7 signature envelope (OSStatus \(status))."
            case .notAProfile:
                return "Decoded content is not a configuration profile property list."
            }
        }
    }

    /// Recover the inner plist bytes and report which envelope shape we found.
    public static func recoverPlist(from data: Data) throws -> (plist: Data, format: SourceFormat) {
        guard !data.isEmpty else { throw DecodeError.empty }

        // 1. Unsigned / raw plist passthrough.
        if isPropertyList(data) {
            return (data, .rawPlist)
        }

        // 2. Assume CMS-wrapped; strip the envelope.
        let content = try cmsContent(of: data)
        guard isPropertyList(content) else {
            throw DecodeError.notAProfile
        }
        return (content, .cmsSigned)
    }

    /// True if `data` parses as a binary or XML property list.
    static func isPropertyList(_ data: Data) -> Bool {
        var format = PropertyListSerialization.PropertyListFormat.xml
        return (try? PropertyListSerialization.propertyList(
            from: data, options: [], format: &format)) != nil
    }

    /// Extract the signed/enveloped content from a CMS message.
    static func cmsContent(of data: Data) throws -> Data {
        var optionalDecoder: CMSDecoder?
        var status = CMSDecoderCreate(&optionalDecoder)
        guard status == errSecSuccess, let decoder = optionalDecoder else {
            throw DecodeError.cmsDecodeFailed(status)
        }

        status = data.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return errSecParam }
            return CMSDecoderUpdateMessage(decoder, base, data.count)
        }
        guard status == errSecSuccess else {
            throw DecodeError.cmsDecodeFailed(status)
        }

        status = CMSDecoderFinalizeMessage(decoder)
        guard status == errSecSuccess else {
            throw DecodeError.cmsDecodeFailed(status)
        }

        var content: CFData?
        status = CMSDecoderCopyContent(decoder, &content)
        guard status == errSecSuccess, let cfData = content else {
            throw DecodeError.cmsDecodeFailed(status)
        }
        return cfData as Data
    }
}
