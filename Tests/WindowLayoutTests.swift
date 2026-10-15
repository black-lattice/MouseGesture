private var layoutChecks = 0
private func checkLayout(_ condition: @autoclosure () -> Bool, _ message: String) {
    layoutChecks += 1
    if !condition() { fatalError(message) }
}
let layoutScreens = [CGRect(x: 0, y: 24, width: 1440, height: 850), CGRect(x: -1920, y: -150, width: 1920, height: 1050)]
let layoutWindow = CGRect(x: 100, y: 100, width: 800, height: 600)
checkLayout(WindowLayout.frame(for: .windowLeft, window: layoutWindow, screens: layoutScreens)
    == CGRect(x: 0, y: 24, width: 720, height: 850), "左半屏保留菜单栏与 Dock 可用区域")
checkLayout(WindowLayout.frame(for: .windowRight, window: layoutWindow, screens: layoutScreens)
    == CGRect(x: 720, y: 24, width: 720, height: 850), "右半屏计算正确")
checkLayout(WindowLayout.frame(for: .windowMaximize, window: layoutWindow, screens: layoutScreens) == layoutScreens[0], "最大化使用可用区域")
checkLayout(WindowLayout.frame(for: .windowCenter, window: layoutWindow, screens: layoutScreens)
    == CGRect(x: 320, y: 149, width: 800, height: 600), "居中保留窗口大小")
let movedLayout = WindowLayout.frame(for: .windowNextDisplay, window: layoutWindow, screens: layoutScreens)!
checkLayout(layoutScreens[1].contains(movedLayout) && movedLayout.size == layoutWindow.size, "移动到负坐标显示器并保持大小")
checkLayout(WindowLayout.frame(for: .windowNextDisplay, window: movedLayout, screens: layoutScreens)!.minX >= 0, "跨屏移动按显示器列表循环")
checkLayout(WindowLayout.frame(for: .windowNextDisplay, window: layoutWindow, screens: [layoutScreens[0]]) == nil, "单显示器不伪造移动成功")
checkLayout(WindowLayout.frame(for: .windowCenter, window: CGRect(x: 0, y: 0, width: 2000, height: 2000), screens: [layoutScreens[0]]) == layoutScreens[0], "超大窗口居中时限制在可用区域")
checkLayout(WindowLayout.frame(for: .windowLeft, window: movedLayout, screens: layoutScreens)?.minX == -1920, "操作以目标窗口所在显示器为准")
checkLayout(WindowLayout.frame(for: .windowLeft, window: layoutWindow, screens: []) == nil, "没有显示器时不执行")
print("窗口布局几何测试通过：\(layoutChecks) 项")
