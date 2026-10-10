// scripts/check.sh appends this harness to the pure core source and runs it with Swift.
// No application is built, launched, or given system permissions by these tests.
var testCount = 0
var failures: [String] = []

func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    testCount += 1
    if !condition() { failures.append(name) }
}

func points(_ values: [(Double, Double)]) -> [CGPoint] {
    values.map { CGPoint(x: $0.0, y: $0.1) }
}

expect(GestureRecognizer.recognize([]) == nil, "空轨迹")
expect(GestureRecognizer.recognize(points([(0, 0)])) == nil, "单点")
expect(GestureRecognizer.recognize(points([(0, 0), (100, 0)])) == [.right], "向右")
expect(GestureRecognizer.recognize(points([(0, 0), (-100, 0)])) == [.left], "负坐标向左")
expect(GestureRecognizer.recognize(points([(0, 0), (0, -100)])) == [.up], "Quartz 坐标向上")
expect(GestureRecognizer.recognize(points([(0, 0), (0, 100)])) == [.down], "向下")
expect(GestureRecognizer.recognize(points([(0, 0), (0, 80), (80, 80)])) == [.down, .right], "下右折线")
expect(GestureRecognizer.recognize(points([(0, 0), (0, 80), (-80, 80)])) == [.down, .left], "下左折线")
expect(GestureRecognizer.recognize(points([(0, 0), (0, -80), (80, -80)])) == [.up, .right], "上右折线")
expect(GestureRecognizer.recognize(points([(0, 0), (0, -80), (0, 0)])) == [.up, .down], "往返轨迹")
expect(GestureRecognizer.recognize(points([(0, 0), (30, 0)])) == nil, "过短不执行")
expect(GestureRecognizer.recognize(points([(0, 0), (30, 0)]), minimumLength: 30) == [.right], "可调长度")
expect(GestureRecognizer.recognize(points([(0, 0), (100, 100)])) == nil, "斜线不误识别")
expect(GestureRecognizer.recognize(points([(0, 0), (100, 20)])) == [.right], "容忍轻微倾斜")
expect(GestureRecognizer.recognize(points([(0, 0), (100, 0), (100, 80), (180, 160)])) == nil, "尾部斜线使整个手势失效")
let jitter = (0...100).map { CGPoint(x: Double($0), y: Double($0 % 3 - 1)) }
expect(GestureRecognizer.recognize(jitter) == [.right], "高频采样抖动")
expect(GestureRecognizer.recognize(points([(0, 0), (80, 0), (80, 80), (0, 80), (0, 0), (80, 0)])) == nil,
       "超过四段拒绝执行")
expect(GestureRecognizer.recognize([CGPoint(x: Double.nan, y: 0), .zero]) == nil, "非法坐标")
expect(GestureRecognizer.recognize(Array(repeating: .zero, count: 2049)) == nil, "过长输入")
let offsetStroke = points([(-1920, -900), (-1920, -820), (-1840, -820)])
expect(GestureRecognizer.recognize(offsetStroke) == [.down, .right], "多显示器负坐标")

var click = Stroke(start: .zero)
click.append(CGPoint(x: 3, y: -2))
expect(click.shouldReplayClick, "普通点击保留右键菜单")
expect(click.recognize(minimumLength: 30) == nil, "抖动不能触发动作")
var drag = Stroke(start: .zero)
drag.append(CGPoint(x: 100, y: 0))
drag.append(.zero)
expect(!drag.shouldReplayClick, "画出再回原点仍是手势，不能误弹菜单")
drag.cancel()
expect(drag.recognize(minimumLength: 30) == nil && !drag.shouldReplayClick, "取消不执行也不弹菜单")
var short = Stroke(start: .zero)
short.append(CGPoint(x: 20, y: 0))
expect(!short.shouldReplayClick && short.recognize(minimumLength: 50) == nil, "短拖拽不触发操作或菜单")
var overflow = Stroke(start: .zero)
for i in 1...2100 { overflow.append(CGPoint(x: Double(i) * 3, y: 0)) }
expect(overflow.isCancelled && overflow.points.count == 2048, "采样上限取消并限制内存")

if failures.isEmpty {
    print("手势识别与点击状态测试通过：\(testCount) 项")
} else {
    failures.forEach { print("失败：\($0)") }
    exit(1)
}
