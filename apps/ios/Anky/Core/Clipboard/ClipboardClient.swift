import UIKit

struct ClipboardClient {
    func readText() -> String? {
        UIPasteboard.general.string
    }

    func copy(_ text: String) {
        UIPasteboard.general.string = text
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
