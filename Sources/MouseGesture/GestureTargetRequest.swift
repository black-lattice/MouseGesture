import AppKit
import ApplicationServices

// Capture WindowServer metadata without asking the target application's accessibility server.
struct GestureTargetRequest {
    let pid: pid_t
    let resolve: () -> GestureTarget?
    var globalTarget: GestureTarget { GestureTarget(pid: pid, window: nil) }
    var bundleIdentifier: String? { NSRunningApplication(processIdentifier: pid)?.bundleIdentifier }
    private static let queue = DispatchQueue(label: "MouseGesture.targetLookup", qos: .userInitiated)

    static func lookup(_ request: Self, completion: @escaping (GestureTarget?) -> Void) -> DispatchWorkItem? {
        let work = DispatchWorkItem {
            let target = request.resolve()
            DispatchQueue.main.async { completion(target) }
        }
        queue.async(execute: work)
        return work
    }

    static func capture(at point: CGPoint) -> Self? {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        if let snapshot = WindowSnapshot.at(point, in: windows) {
            return Self(pid: snapshot.pid) {
                // Never retarget to a window that moved over the gesture's starting point.
                guard snapshot.isStillAt(point), let target = GestureTarget.at(point),
                      target.pid == snapshot.pid, let window = target.window,
                      snapshot.matches(window), snapshot.isStillAt(point) else { return nil }
                return target
            }
        }
        // The desktop has no ordinary window, but global actions still work there.
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            return nil
        }
        return Self(pid: finder.processIdentifier, resolve: { nil })
    }
}

private struct WindowSnapshot: Equatable {
    let pid: pid_t
    let number: CGWindowID
    let bounds: CGRect

    static func at(_ point: CGPoint, in windows: [[String: Any]]) -> Self? {
        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer >= 0,
                  layer < CGWindowLevelForKey(.statusWindow),
                  let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  let number = window[kCGWindowNumber as String] as? UInt32,
                  let dictionary = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary), bounds.contains(point) else { continue }
            return Self(pid: pid, number: number, bounds: bounds)
        }
        return nil
    }

    func isStillAt(_ point: CGPoint) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return Self.at(point, in: windows) == self
    }

    func matches(_ window: AXUIElement) -> Bool {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return false
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size) else { return false }
        return abs(position.x - bounds.minX) <= 1 && abs(position.y - bounds.minY) <= 1
            && abs(size.width - bounds.width) <= 1 && abs(size.height - bounds.height) <= 1
    }
}
