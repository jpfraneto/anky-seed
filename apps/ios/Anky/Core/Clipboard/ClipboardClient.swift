import UIKit

struct ClipboardClient {
    func copy(_ text: String) {
        UIPasteboard.general.string = text
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
