import Foundation

enum MouseButton: String, CaseIterable, Identifiable {
    case middle, back, forward
    var id: String { rawValue }
    var title: String {
        switch self {
        case .middle: return "中键"
        case .back: return "后退侧键"
        case .forward: return "前进侧键"
        }
    }
    var defaultNumber: Int64 {
        switch self {
        case .middle: return 2
        case .back: return 3
        case .forward: return 4
        }
    }
}

struct MouseButtonBinding: Codable, Equatable {
    var buttonNumber: Int64
    var shortcut: KeyboardShortcut?
}

extension Preferences {
    func mouseBinding(for button: MouseButton) -> MouseButtonBinding {
        mouseBindings[button.rawValue] ?? MouseButtonBinding(buttonNumber: button.defaultNumber)
    }

    func setMouseShortcut(_ shortcut: KeyboardShortcut?, for button: MouseButton) {
        var binding = mouseBinding(for: button)
        binding.shortcut = shortcut
        mouseBindings[button.rawValue] = binding
    }

    @discardableResult
    func setMouseButtonNumber(_ number: Int64, for button: MouseButton) -> Bool {
        guard (2...31).contains(number) else { return false }
        var updated = mouseBindings
        var binding = mouseBinding(for: button)
        // Swap physical buttons so opposite side-button numbering never creates duplicates.
        if let other = MouseButton.allCases.first(where: { $0 != button && mouseBinding(for: $0).buttonNumber == number }) {
            var otherBinding = mouseBinding(for: other)
            otherBinding.buttonNumber = binding.buttonNumber
            updated[other.rawValue] = otherBinding
        }
        binding.buttonNumber = number
        updated[button.rawValue] = binding
        mouseBindings = updated
        return true
    }
}
