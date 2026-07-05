import Foundation

#if canImport(DeviceCheck)
import DeviceCheck
#endif

enum DeviceCheckTrialProofProvider {
    static func makeToken() async -> String? {
        #if canImport(DeviceCheck)
        guard DCDevice.current.isSupported else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            DCDevice.current.generateToken { data, error in
                guard let data, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: data.base64EncodedString())
            }
        }
        #else
        return nil
        #endif
    }
}

enum AnkyAppVersion {
    static var headerValue: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        return "\(version)(\(build))"
    }
}
