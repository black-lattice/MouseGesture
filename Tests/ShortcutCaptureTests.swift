// Exercise the event filter without installing taps or posting system events.
private var captureChecks = 0
private func checkCapture(_ condition: @autoclosure () -> Bool, _ message: String) {
    captureChecks += 1
    if !condition() { fatalError(message) }
}
private func captureEvent(_ code: CGKeyCode, down: Bool, repeatKey: Bool = false) -> CGEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
    event.flags = [.maskCommand, .maskShift]
    event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
    return event
}
private var captureFilter = ShortcutCapture()
private let captureDown = captureEvent(7, down: true)
private let captureUp = captureEvent(7, down: false)
private let downResult = captureFilter.consume(type: .keyDown, event: captureDown)
checkCapture(downResult.swallow && downResult.completed == nil, "按下组合键即拦截，不提前结束录制")
private let repeatResult = captureFilter.consume(type: .keyDown, event: captureEvent(7, down: true, repeatKey: true))
checkCapture(repeatResult.swallow && repeatResult.completed == nil, "长按重复事件被拦截且不重复录入")
private let upResult = captureFilter.consume(type: .keyUp, event: captureUp)
checkCapture(upResult.swallow && upResult.completed?.type == .keyDown, "松开主键也被拦截，并交付最初的按下事件")
checkCapture(upResult.completed?.getIntegerValueField(.keyboardEventKeycode) == 7
             && upResult.completed?.flags == captureDown.flags, "松开时保留按下时的键位和修饰键")
private let capturedShortcut = KeyboardShortcut.recorded(from: NSEvent(cgEvent: upResult.completed!)!)
checkCapture(capturedShortcut?.keyCode == 7 && capturedShortcut?.label == "⇧ ⌘ X", "系统事件可转换为可保存的快捷键")
checkCapture(!captureFilter.consume(type: .keyUp, event: captureUp).swallow, "多余的松开事件放行")
checkCapture(!captureFilter.consume(type: .flagsChanged, event: captureDown).swallow, "修饰键事件不被错误录为主键")
_ = captureFilter.consume(type: .keyDown, event: captureDown)
_ = captureFilter.consume(type: .keyDown, event: captureEvent(35, down: true))
checkCapture(captureFilter.consume(type: .keyUp, event: captureUp).completed == nil, "重叠主键尚未全部松开时继续拦截")
private let overlapResult = captureFilter.consume(type: .keyUp, event: captureEvent(35, down: false))
checkCapture(overlapResult.swallow && overlapResult.completed?.getIntegerValueField(.keyboardEventKeycode) == 7,
             "重叠主键全部松开后只录入第一个组合")
captureFilter = ShortcutCapture()
_ = captureFilter.consume(type: .keyDown, event: captureEvent(7, down: true, repeatKey: true))
checkCapture(captureFilter.consume(type: .keyUp, event: captureUp).completed == nil, "录制前已按住的键不会因自动重复被记录")
_ = captureFilter.consume(type: .keyDown, event: captureDown)
captureFilter = ShortcutCapture()
checkCapture(!captureFilter.consume(type: .keyUp, event: captureUp).swallow, "停止并清理后不残留捕获状态")
private let escapeDown = captureEvent(53, down: true)
escapeDown.flags = []
_ = captureFilter.consume(type: .keyDown, event: escapeDown)
private let escapeResult = captureFilter.consume(type: .keyUp, event: captureEvent(53, down: false))
checkCapture(KeyboardShortcut.isCancel(NSEvent(cgEvent: escapeResult.completed!)!), "Esc 的按下与松开被捕获后用于取消")
print("快捷键事件拦截测试通过：\(captureChecks) 项")
