import Foundation
import GestureCore

struct CustomAction: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var shortcut: KeyboardShortcut
    var pattern: String
    var directions: [Direction] { pattern.compactMap { Direction(rawValue: String($0)) } }
    var arrows: String { directions.map(\.arrow).joined(separator: " ") }
}

struct CustomActionDraft: Identifiable {
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
