import Foundation

#if os(iOS) && canImport(FamilyControls)
import FamilyControls

struct WriteBeforeScrollScreenTimeSelectionStore {
    private let defaults: UserDefaults
    private let selectionKey = "writeBeforeScroll.familyActivitySelection.v1"
    private let blockedAppSelectionStore: BlockedAppSelectionStore
    private let stateStore: WriteBeforeScrollScreenTimeStateStore

    init(defaults: UserDefaults = AnkyAppGroupStorage.userDefaults()) {
        self.defaults = defaults
        self.blockedAppSelectionStore = BlockedAppSelectionStore(defaults: defaults)
        self.stateStore = WriteBeforeScrollScreenTimeStateStore(defaults: defaults)
    }

    func loadSelection() -> FamilyActivitySelection {
        guard let data = defaults.data(forKey: selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return selection
    }

    func saveSelection(_ selection: FamilyActivitySelection) {
        guard let data = try? JSONEncoder().encode(selection) else {
            stateStore.update { state in
                state.lastErrorMessage = "Could not encode selected app tokens."
            }
            return
        }

        defaults.set(data, forKey: selectionKey)
        blockedAppSelectionStore.save(
            BlockedAppSelectionSnapshot(
                encodedSelectionData: data,
                selectedApplicationCount: selection.applicationTokens.count,
                selectedCategoryCount: selection.categoryTokens.count,
                updatedAt: Date()
            )
        )
        stateStore.update { state in
            state.selectedApplicationCount = selection.applicationTokens.count
            state.selectedCategoryCount = selection.categoryTokens.count
            state.selectedWebDomainCount = selection.webDomainTokens.count
            state.lastErrorMessage = nil
        }
    }

    func clearSelection() {
        defaults.removeObject(forKey: selectionKey)
        blockedAppSelectionStore.clear()
        stateStore.update { state in
            state.selectedApplicationCount = 0
            state.selectedCategoryCount = 0
            state.selectedWebDomainCount = 0
        }
    }
}
#endif
