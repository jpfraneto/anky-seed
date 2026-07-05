import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// The writer's optional selfie, taken during onboarding and worn across
/// the app. Kept as a single JPEG in the app's Documents directory —
/// never in the App Group, never off the device.
struct AvatarStore {
    private static let fileName = "avatar.jpg"

    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var fileURL: URL {
        directory.appendingPathComponent(Self.fileName)
    }

    var hasAvatar: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    func loadData() -> Data? {
        try? Data(contentsOf: fileURL)
    }

    func save(data: Data) {
        try? data.write(to: fileURL, options: .atomic)
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    #if canImport(UIKit)
    func loadImage() -> UIImage? {
        guard let data = loadData() else {
            return nil
        }
        return UIImage(data: data)
    }

    func save(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            return
        }
        save(data: data)
    }
    #endif
}
