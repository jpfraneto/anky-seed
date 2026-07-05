import Foundation

enum CreditIdentity {
    static func appUserID(for identity: WriterIdentity) -> String {
        identity.address
    }
}
