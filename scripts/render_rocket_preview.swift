import AppKit

final class RocketPreviewView: NSView {
    let progress: Int

    init(progress: Int, frame: NSRect) {
        self.progress = progress
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let completed = CGFloat(progress) / 7
        NSColor(calibratedWhite: 0.1, alpha: 0.72).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 16, yRadius: 16).fill()

        let rocket = NSRect(x: 25, y: 36, width: 76, height: 160)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: rocket.minY, width: bounds.width, height: rocket.height * completed)).addClip()
        NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(ovalIn: rocket).fill()
        NSColor(calibratedRed: 0.34, green: 0.68, blue: 0.93, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 46, y: 125, width: 34, height: 34)).fill()
        NSColor(calibratedRed: 0.93, green: 0.35, blue: 0.28, alpha: 1).setFill()
        let leftFin = NSBezierPath()
        leftFin.move(to: NSPoint(x: 38, y: 82)); leftFin.line(to: NSPoint(x: 16, y: 49)); leftFin.line(to: NSPoint(x: 43, y: 60)); leftFin.close(); leftFin.fill()
        let rightFin = NSBezierPath()
        rightFin.move(to: NSPoint(x: 88, y: 82)); rightFin.line(to: NSPoint(x: 111, y: 49)); rightFin.line(to: NSPoint(x: 84, y: 60)); rightFin.close(); rightFin.fill()
        NSColor(calibratedRed: 1, green: 0.64, blue: 0.15, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 48, y: 24, width: 30, height: 48)).fill()
        NSGraphicsContext.restoreGraphicsState()

        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        NSAttributedString(string: "月まで \(progress)/7", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]).draw(in: NSRect(x: 8, y: 9, width: bounds.width - 16, height: 18))
    }
}

guard CommandLine.arguments.count == 2 else { fatalError("Output path required") }
let size = NSSize(width: 126, height: 220)
let view = RocketPreviewView(progress: 9, frame: NSRect(origin: .zero, size: size))
let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
view.cacheDisplay(in: view.bounds, to: bitmap)
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
