import Foundation
import Combine
import GestureCore

struct CustomAction: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var shortcut: KeyboardShortcut
    var pattern: String
    var directions: [Direction] { pattern.compactMap { Direction(rawValue: String($0)) } }
    var arrows: String { directions.map(\.arrow).joined(separator: " ") }
}

struct CustomActionDraft: Identifiable, Equatable {
    var id: UUID
    var name: String
    var shortcut: KeyboardShortcut?
    var directions: [Direction]
    var gestureError: String?
    var shortcutError: String?

    init(action: CustomAction? = nil) {
        id = action?.id ?? UUID()
        name = action?.name ?? ""
        shortcut = action?.shortcut
        directions = action?.directions ?? []
    }
}

// Publish edits only to the row that owns this draft, not the entire settings form.
final class CustomActionDraftModel: ObservableObject, Identifiable {
    let id: UUID
    @Published var value: CustomActionDraft

    init(_ value: CustomActionDraft) {
        id = value.id
        self.value = value
    }
}
