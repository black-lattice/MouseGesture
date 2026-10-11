// Compare real AppKit pixels after partial updates with a fresh full redraw.
// No visible application, event injection, or user preferences are involved.
private var renderChecks = 0
private var renderFailures: [String] = []
private func checkRendering(_ condition: @autoclosure () -> Bool, _ message: String) {
    renderChecks += 1
    if !condition() { renderFailures.append(message) }
}
private func trailBitmap(scale: Int = 1) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800 * scale, pixelsHigh: 600 * scale,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.bitmapData!.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    return bitmap
}
private func renderTrail(_ view: TrailView, into bitmap: NSBitmapImageRep, dirty: CGRect) {
    guard !dirty.isNull && !dirty.isEmpty else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(bitmap.pixelsWide) / 800)
    transform.concat()
    view.draw(dirty)
    NSGraphicsContext.restoreGraphicsState()
}
private func trailPixels(_ bitmap: NSBitmapImageRep) -> Data {
    Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
}
private let renderBounds = CGRect(x: 0, y: 0, width: 800, height: 600)
private let renderCases: [([CGPoint], String)] = [
    ([CGPoint(x: 100, y: 100), CGPoint(x: 210.5, y: 100)], "→ 截图"),
    ([CGPoint(x: 100, y: 100), CGPoint(x: 210.5, y: 100), CGPoint(x: 210.5, y: 260.5)], "→ ↓ 自定义功能名称"),
    ([CGPoint(x: 100, y: 100), CGPoint(x: 210.5, y: 100), CGPoint(x: 210.5, y: 260.5)], "短提示"),
    ([CGPoint(x: 650, y: 590), CGPoint(x: 790, y: 500)], "边缘提示"),
    ([CGPoint(x: -100, y: 300), CGPoint(x: 900, y: 300)], "两端在屏幕外"),
    ([CGPoint(x: -200, y: -100), CGPoint(x: -50, y: -100)], "屏幕外"),
    ([CGPoint(x: 100, y: 300), CGPoint(x: 200, y: 300)], "第一行\n第二行\n第三行"),
    ([CGPoint(x: 100, y: 300), CGPoint(x: 320.5, y: 400.5)], "第一行\n第二行\n第三行"),
    ([CGPoint(x: 100, y: 300), CGPoint(x: 320.5, y: 400.5)], "缩短"),
    ([CGPoint(x: 20, y: 20), CGPoint(x: 60.5, y: 20)], "底部\n多行\n提示"),
    ([CGPoint(x: 700, y: 590), CGPoint(x: 799.5, y: 599.5)], "边缘 👨‍👩‍👧‍👦\n中文 ágj\n第三行"),
    ([], "")
]
private var firstDirtyArea: CGFloat = 0
for scale in [1, 2] {
    let incrementalTrail = TrailView(frame: renderBounds)
    let incrementalBitmap = trailBitmap(scale: scale)
    for (index, sample) in renderCases.enumerated() {
        let dirty = incrementalTrail.update(points: sample.0, label: sample.1)
        if index == 0 { firstDirtyArea = dirty.width * dirty.height }
        renderTrail(incrementalTrail, into: incrementalBitmap, dirty: dirty)
        let reference = TrailView(frame: renderBounds)
        reference.update(points: sample.0, label: sample.1)
        let referenceBitmap = trailBitmap(scale: scale)
        renderTrail(reference, into: referenceBitmap, dirty: renderBounds)
        checkRendering(trailPixels(incrementalBitmap) == trailPixels(referenceBitmap),
                       "局部与完整重绘像素一致：\(scale)x 场景 \(index)，轨迹与文字无裁切、残影")
        checkRendering(incrementalTrail.update(points: sample.0, label: sample.1).isNull,
                       "相同轨迹和提示不重复绘制：\(scale)x 场景 \(index)")
    }
    checkRendering(trailPixels(incrementalBitmap) == trailPixels(trailBitmap(scale: scale)),
                   "\(scale)x 清空后透明画布没有残留")
}
checkRendering(firstDirtyArea > 0 && firstDirtyArea < renderBounds.width * renderBounds.height / 10,
               "短轨迹的刷新面积小于整屏的十分之一")
private let crossing = TrailView(frame: renderBounds)
crossing.update(points: [CGPoint(x: -100, y: 300), CGPoint(x: 900, y: 300)], label: "跨屏")
checkRendering(!crossing.drawingBounds.isEmpty, "跨屏线段即使两端均在屏幕外仍绘制")
if renderFailures.isEmpty {
    print("轨迹局部重绘像素测试通过：\(renderChecks) 项（1x / 2x，短轨迹面积 \(Int(firstDirtyArea)) / 480000 平方点）")
} else {
    renderFailures.forEach { print("失败：\($0)") }
    exit(1)
}
