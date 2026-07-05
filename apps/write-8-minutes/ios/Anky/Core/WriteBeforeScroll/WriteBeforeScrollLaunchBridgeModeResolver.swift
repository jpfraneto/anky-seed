import Foundation

enum WriteBeforeScrollLaunchBridgeModeResolver {
    static func resolve() -> WriteBeforeScrollLaunchBridgeMode {
        // TODO: Enable `.directOpen` here when the project builds with an SDK whose
        // Swift interface exposes `ShieldActionResponse.openParentalControlsApp`.
        // The local Xcode SDK exports the binary symbol but does not expose the Swift
        // enum case, so referencing it would leave the project uncompilable.
        if #available(iOS 26.5, *) {
            return .notification
        }
        return .notification
    }

    static var directOpenCompatibilityNote: String {
        "Enable direct open when ShieldActionResponse.openParentalControlsApp is exposed by the SDK."
    }
}
