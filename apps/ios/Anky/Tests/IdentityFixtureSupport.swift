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
        let repoRoot = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repoRoot
            .appendingPathComponent("protocol")
            .appendingPathComponent("identity")
            .appendingPathComponent("fixtures")
            .appendingPathComponent("base_eoa_v1_mainnet.json")
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(AnkyIdentityFixture.self, from: data)
    }
}
