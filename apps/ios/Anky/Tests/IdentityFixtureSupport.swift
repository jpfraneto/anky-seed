import Foundation

struct AnkyIdentityFixture: Decodable {
    let identityVersion: String
    let accountKind: String
    let chainId: UInt64
    let accountId: String
    let address: String
    let mnemonic: String
    let derivationPath: String
    let body: String
    let bodySha256: String
    let requestTime: UInt64
    let client: String
    let signature: String
    let recoveredAddress: String
}

enum AnkyIdentityFixtureLoader {
    static func mainnet(filePath: String = #filePath) throws -> AnkyIdentityFixture {
        // Walk up from this file until the repo root (the directory that
        // contains protocol/) so the fixtures survive app-folder moves.
        var candidate = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        for _ in 0..<12 {
            let protocolDir = candidate.appendingPathComponent("protocol/identity/fixtures")
            if fileManager.fileExists(atPath: protocolDir.path) {
                let fixtureURL = protocolDir.appendingPathComponent("base_eoa_v1_mainnet.json")
                let data = try Data(contentsOf: fixtureURL)
                return try JSONDecoder().decode(AnkyIdentityFixture.self, from: data)
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
