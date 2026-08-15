import Foundation

struct AnkyInferenceReceipt: Codable, Hashable {
    enum Access: String, Codable {
        case free
        case supported
    }

    let access: Access
    let provider: String
    let model: String?
    let costUsd: Double?

    var disclosureLine: String {
        let intelligence = access == .free ? "free intelligence" : "supported intelligence"
        let modelName = model?.isEmpty == false ? model! : provider
        let cost: String
        if let costUsd {
            cost = costUsd == 0 ? "$0" : String(format: "$%.6f", costUsd)
        } else {
            cost = "cost not reported"
        }
        return "\(intelligence) · \(modelName) · \(cost)"
    }
}

struct AnkyConversationMessage: Codable, Hashable, Identifiable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let content: String
    let createdAt: Date
    let inference: AnkyInferenceReceipt?

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = Date(),
        inference: AnkyInferenceReceipt? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.inference = inference
    }
}

struct LocalReflection: Codable, Hashable, Identifiable {
    var id: String { hash }

    let hash: String
    let title: String
    let reflection: String
    let tags: [String]
    let createdAt: Date
    let inference: AnkyInferenceReceipt?
    var conversation: [AnkyConversationMessage]

    init(
        hash: String,
        title: String,
        reflection: String,
        tags: [String] = [],
        createdAt: Date,
        inference: AnkyInferenceReceipt? = nil,
        conversation: [AnkyConversationMessage] = []
    ) {
        self.hash = hash
        self.title = title
        self.reflection = reflection
        self.tags = tags
        self.createdAt = createdAt
        self.inference = inference
        self.conversation = conversation
    }

    enum CodingKeys: String, CodingKey {
        case hash
        case title
        case reflection
        case tags
        case createdAt
        case inference
        case conversation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hash = try container.decode(String.self, forKey: .hash)
        title = try container.decode(String.self, forKey: .title)
        reflection = try container.decode(String.self, forKey: .reflection)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        inference = try container.decodeIfPresent(AnkyInferenceReceipt.self, forKey: .inference)
        conversation = try container.decodeIfPresent([AnkyConversationMessage].self, forKey: .conversation) ?? []
    }
}

struct ReflectionStore {
    private let directoryURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(directoryURL: base.appendingPathComponent("Anky/reflections", isDirectory: true), fileManager: fileManager)
    }

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func save(_ reflection: LocalReflection) throws {
        let data = try JSONEncoder.reflectionEncoder.encode(reflection)
        try data.write(to: url(for: reflection.hash), options: [.atomic])
    }

    func saveConversation(_ messages: [AnkyConversationMessage], hash: String) throws {
        guard var reflection = load(hash: hash) else { return }
        reflection.conversation = messages
        try save(reflection)
    }

    func load(hash: String) -> LocalReflection? {
        guard let data = try? Data(contentsOf: url(for: hash)) else {
            return nil
        }
        return try? JSONDecoder.reflectionDecoder.decode(LocalReflection.self, from: data)
    }

    func list() -> [LocalReflection] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )) ?? []

        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> LocalReflection? in
                guard let data = try? Data(contentsOf: url) else {
                    return nil
                }
                return try? JSONDecoder.reflectionDecoder.decode(LocalReflection.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func fileURLs() -> [URL] {
        ((try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )) ?? [])
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func delete(hash: String) throws {
        let reflectionURL = url(for: hash)
        guard fileManager.fileExists(atPath: reflectionURL.path) else {
            return
        }
        try fileManager.removeItem(at: reflectionURL)
    }

    func clear() throws {
        let urls = fileURLs()
        for url in urls {
            try fileManager.removeItem(at: url)
        }
    }

    private func url(for hash: String) -> URL {
        directoryURL.appendingPathComponent("\(hash).json")
    }
}

private extension JSONEncoder {
    static var reflectionEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var reflectionDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
