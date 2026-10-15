private var styleChecks = 0
private let styledPoints = [CGPoint(x: 100, y: 100), CGPoint(x: 400, y: 100)]
for scale in [1, 2] {
    let view = TrailView(frame: renderBounds)
    let bitmap = trailBitmap(scale: scale)
    for (color, width, visible, label) in [(NSColor.systemOrange, CGFloat(10), true, "宽轨迹"),
                                          (.systemBlue, 2, true, ""), (.systemPink, 6, false, "仅提示"),
                                          (.white, 4, false, ""), (.systemTeal, 4, true, "恢复轨迹")] {
        let dirty = view.update(points: styledPoints, label: label, color: color, width: width, showTrail: visible)
        renderTrail(view, into: bitmap, dirty: dirty)
        let reference = TrailView(frame: renderBounds)
        reference.update(points: styledPoints, label: label, color: color, width: width, showTrail: visible)
        let referenceBitmap = trailBitmap(scale: scale)
        renderTrail(reference, into: referenceBitmap, dirty: renderBounds)
        guard trailPixels(bitmap) == trailPixels(referenceBitmap) else { fatalError("更改颜色、粗细或显示开关后局部重绘有残影") }
        styleChecks += 1
    }
}
print("轨迹颜色、宽度与独立提示像素测试通过：\(styleChecks) 项")
