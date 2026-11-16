import AppKit
import Foundation

enum RocketSchedule {
    static let completionDays = 7
    static let artworkStages = 14
    static let artworkStagesPerDay = artworkStages / completionDays
}

private final class DiaryStore {
    private let fileManager = FileManager.default
    let root: URL

    init() {
        root = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/RabbitDesktopPet/.diary", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func hasEntry(on date: Date = Date()) -> Bool {
        fileManager.fileExists(atPath: entryURL(for: date).path)
    }

    func save(_ text: String, on date: Date = Date()) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try text.write(to: entryURL(for: date), atomically: true, encoding: .utf8)
    }

    func allEntries() -> [(date: Date, text: String)] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { url -> (Date, String)? in
            guard url.pathExtension == "txt",
                  !url.lastPathComponent.hasPrefix("weekly-"),
                  let date = Self.dayFormatter.date(from: url.deletingPathExtension().lastPathComponent),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return (date, text)
        }.sorted { $0.0 < $1.0 }
    }

    func rocketProgress() -> Int {
        let count = allEntries().count
        guard count > 0 else { return 0 }
        return (count - 1) % RocketSchedule.completionDays + 1
    }

    func completedWeeklyBatch() -> (id: String, entries: [(Date, String)])? {
        let entries = allEntries()
        guard entries.count >= 7, entries.count.isMultiple(of: 7), let last = entries.last else { return nil }
        let id = Self.dayFormatter.string(from: last.0)
        return (id, Array(entries.suffix(7)))
    }

    private func entryURL(for date: Date) -> URL {
        root.appendingPathComponent(Self.dayFormatter.string(from: date)).appendingPathExtension("txt")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum ExpeditionStatus: String {
    case home
    case departing
    case away
    case returning
}

enum ExpeditionPersistence {
    private static let statusKey = "expedition.status"
    private static let rabbitKey = "expedition.rabbit-index"

    static var status: ExpeditionStatus {
        ExpeditionStatus(rawValue: UserDefaults.standard.string(forKey: statusKey) ?? "") ?? .home
    }

    static var rabbitIndex: Int? {
        guard status != .home else { return nil }
        return UserDefaults.standard.object(forKey: rabbitKey) as? Int
    }

    static func set(_ status: ExpeditionStatus, rabbitIndex: Int?) {
        UserDefaults.standard.set(status.rawValue, forKey: statusKey)
        if let rabbitIndex {
            UserDefaults.standard.set(rabbitIndex, forKey: rabbitKey)
        } else {
            UserDefaults.standard.removeObject(forKey: rabbitKey)
        }
    }
}

@MainActor
private final class DiaryInputController: NSObject, NSWindowDelegate, NSTextViewDelegate {
    private let window: NSWindow
    private let textView = NSTextView()
    private let saveButton = NSButton(title: "うさぎにあずける", target: nil, action: nil)
    private let onSave: (String) -> Void

    init(onSave: @escaping (String) -> Void) {
        self.onSave = onSave
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 330),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "うさぎの日記"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self

        let content = NSView(frame: window.contentView?.bounds ?? .zero)
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        let question = NSTextField(labelWithString: "今日はどうだった？")
        question.font = .systemFont(ofSize: 22, weight: .bold)
        question.frame = NSRect(x: 24, y: 277, width: 380, height: 30)
        content.addSubview(question)

        let hint = NSTextField(labelWithString: "1文字からで大丈夫。長さに制限はないよ。")
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 25, y: 251, width: 380, height: 20)
        content.addSubview(hint)

        let scroll = NSScrollView(frame: NSRect(x: 24, y: 67, width: 382, height: 176))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 16)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = self
        scroll.documentView = textView
        content.addSubview(scroll)

        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.isEnabled = false
        saveButton.frame = NSRect(x: 245, y: 20, width: 160, height: 34)
        saveButton.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(saveButton)
    }

    func show() {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
    }

    func textDidChange(_ notification: Notification) {
        saveButton.isEnabled = !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc private func save() {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSave(text)
        window.orderOut(nil)
    }
}

@MainActor
private final class WeeklyReviewController: NSObject, NSWindowDelegate {
    private let window: NSWindow

    init(entries: [(date: Date, text: String)]) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "7日間のふりかえり"
        window.minSize = NSSize(width: 480, height: 360)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces]
        window.delegate = self

        let content = NSView(frame: window.contentView?.bounds ?? .zero)
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        let heading = NSTextField(labelWithString: "7日間、ちゃんと書けたよ！")
        heading.font = .systemFont(ofSize: 24, weight: .bold)
        heading.frame = NSRect(x: 28, y: 505, width: 560, height: 32)
        heading.autoresizingMask = [.width, .minYMargin]
        content.addSubview(heading)

        let hint = NSTextField(labelWithString: "この1週間に書いたことを、日付ごとに並べたよ。")
        hint.font = .systemFont(ofSize: 14)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 29, y: 478, width: 560, height: 22)
        hint.autoresizingMask = [.width, .minYMargin]
        content.addSubview(hint)

        let scroll = NSScrollView(frame: NSRect(x: 24, y: 60, width: 572, height: 405))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textStorage?.setAttributedString(Self.makeText(entries: entries))
        scroll.documentView = textView
        content.addSubview(scroll)

        let closeButton = NSButton(title: "とじる", target: self, action: #selector(close))
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\r"
        closeButton.frame = NSRect(x: 474, y: 16, width: 122, height: 32)
        closeButton.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(closeButton)
    }

    func show() {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func close() {
        window.orderOut(nil)
    }

    private static func makeText(entries: [(date: Date, text: String)]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日（E）"

        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineSpacing = 4
        bodyStyle.paragraphSpacing = 18

        for entry in entries {
            result.append(NSAttributedString(
                string: "\(formatter.string(from: entry.date))\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 18, weight: .bold),
                    .foregroundColor: NSColor.labelColor,
                ]
            ))
            result.append(NSAttributedString(
                string: "\(entry.text)\n\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 16),
                    .foregroundColor: NSColor.textColor,
                    .paragraphStyle: bodyStyle,
                ]
            ))
        }
        return result
    }
}

@MainActor
private final class DiaryCallBubbleView: NSView {
    var onClick: (() -> Void)?

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.97).setFill()
        let body = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 12), xRadius: 18, yRadius: 18)
        body.fill()
        NSColor(calibratedWhite: 0.25, alpha: 0.2).setStroke()
        body.lineWidth = 1
        body.stroke()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 38, y: 14))
        tail.line(to: NSPoint(x: 52, y: 1))
        tail.line(to: NSPoint(x: 64, y: 14))
        tail.close()
        NSColor.white.setFill()
        tail.fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        NSAttributedString(string: "日記のじかんだよ！", attributes: [
            .font: NSFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.32, green: 0.20, blue: 0.12, alpha: 1),
            .paragraphStyle: paragraph,
        ]).draw(in: NSRect(x: 10, y: 28, width: bounds.width - 20, height: 22))
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

@MainActor
private final class RocketView: NSView {
    private let atlas: NSImage
    var progress = 0 { didSet { needsDisplay = true } }
    var showsRocket = true { didSet { needsDisplay = true } }
    var isTestMode = false { didSet { needsDisplay = true } }

    init(atlas: NSImage, frame: NSRect) {
        self.atlas = atlas
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.1, alpha: 0.72).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 16, yRadius: 16).fill()

        if showsRocket, progress > 0 {
            drawRocket(stage: progress, in: NSRect(x: 0, y: 28, width: 126, height: 190))
        }

        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let label = isTestMode
            ? "TEST \(progress)/\(RocketSchedule.completionDays)"
            : "月まで \(progress)/\(RocketSchedule.completionDays)"
        NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]).draw(in: NSRect(x: 8, y: 9, width: bounds.width - 16, height: 18))
    }

    private func drawRocket(stage: Int, in destination: NSRect) {
        let completedDay = min(max(stage, 1), RocketSchedule.completionDays)
        let artworkStage = completedDay * RocketSchedule.artworkStagesPerDay
        let index = min(artworkStage, RocketSchedule.artworkStages) - 1
        let column = index % 7
        let topDownRow = index / 7
        let cellWidth = atlas.size.width / 7
        let cellHeight = atlas.size.height / 2
        let source = NSRect(
            x: CGFloat(column) * cellWidth,
            y: CGFloat(1 - topDownRow) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        NSGraphicsContext.current?.imageInterpolation = .none
        atlas.draw(in: destination, from: source, operation: .sourceOver, fraction: 1)
    }
}

@MainActor
private final class RocketFlightView: NSView {
    enum Mode { case flight, explosion }

    private let atlas: NSImage
    private let explosionAtlas: NSImage
    var mode: Mode = .flight { didSet { needsDisplay = true } }
    var scale: CGFloat = 1 { didSet { needsDisplay = true } }
    var rotationDegrees: CGFloat = 0 { didSet { needsDisplay = true } }
    var explosionProgress: CGFloat = 0 { didSet { needsDisplay = true } }

    init(atlas: NSImage, explosionAtlas: NSImage, frame: NSRect) {
        self.atlas = atlas
        self.explosionAtlas = explosionAtlas
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        if mode == .explosion {
            drawPixelExplosion()
            return
        }

        let cellWidth = atlas.size.width / 7
        let cellHeight = atlas.size.height / 2
        let source = NSRect(x: 6 * cellWidth, y: 0, width: cellWidth, height: cellHeight)
        let size = NSSize(width: 126 * scale, height: 190 * scale)
        let destination = NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: bounds.midX, yBy: bounds.midY)
        transform.rotate(byDegrees: rotationDegrees)
        transform.translateX(by: -bounds.midX, yBy: -bounds.midY)
        transform.concat()
        atlas.draw(in: destination, from: source, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawPixelExplosion() {
        let t = min(max(explosionProgress, 0), 1)
        let frameIndex = min(7, Int(t * 8))
        let column = frameIndex % 4
        let topDownRow = frameIndex / 4
        let cellWidth = explosionAtlas.size.width / 4
        let cellHeight = explosionAtlas.size.height / 2
        let source = NSRect(
            x: CGFloat(column) * cellWidth,
            y: CGFloat(1 - topDownRow) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        explosionAtlas.draw(
            in: bounds.insetBy(dx: 10, dy: 10),
            from: source,
            operation: .sourceOver,
            fraction: 1
        )
    }
}

@MainActor
private final class MoonView: NSView {
    private let image: NSImage

    init(image: NSImage, frame: NSRect) {
        self.image = image
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

@MainActor
final class DiaryCoordinator {
    enum TestState: Equatable {
        case inactive
        case building(Int)
        case departing
        case away
        case returning
        case finished
    }

    enum TestAction {
        case none
        case depart
        case returnHome
    }

    private let store = DiaryStore()
    private let rabbitWindows: () -> [NSWindow]
    private let onCallingChanged: (Int?) -> Void
    private let onReward: (Int) -> Void
    private let onWeeklyMessage: (String) -> Void
    private let onDeparture: () -> Void
    private let onReturn: () -> Void
    private var inputController: DiaryInputController?
    private var weeklyReviewController: WeeklyReviewController?
    private var bubbleWindow: NSWindow?
    private var rocketWindow: NSWindow?
    private var rocketView: RocketView?
    private var flightWindow: NSWindow?
    private var flightView: RocketFlightView?
    private var moonWindow: NSWindow?
    private var expeditionTimer: Timer?
    private var rocketHomeOrigin: NSPoint?
    private var launchCompletion: (() -> Void)?
    private var returnCompletion: (() -> Void)?
    private(set) var testState: TestState = .inactive
    private var callingIndex: Int?
    private var timer: Timer?
    private var lastPromptDay = ""

    init(
        rabbitWindows: @escaping () -> [NSWindow],
        onCallingChanged: @escaping (Int?) -> Void,
        onReward: @escaping (Int) -> Void,
        onWeeklyMessage: @escaping (String) -> Void,
        onDeparture: @escaping () -> Void,
        onReturn: @escaping () -> Void
    ) {
        self.rabbitWindows = rabbitWindows
        self.onCallingChanged = onCallingChanged
        self.onReward = onReward
        self.onWeeklyMessage = onWeeklyMessage
        self.onDeparture = onDeparture
        self.onReturn = onReturn
    }

    func start() {
        showRocket()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkSchedule() }
        }
        checkSchedule()
        showWeeklyReviewIfReady()
    }

    func showDiaryNow() {
        guard testState == .inactive else { return }
        guard !store.hasEntry() else {
            onWeeklyMessage("今日の日記はもうあずかってるよ！")
            return
        }
        beginCalling()
    }

    private func checkSchedule() {
        guard testState == .inactive else { return }
        let calendar = Calendar.current
        let now = Date()
        let day = Self.dayFormatter.string(from: now)
        guard calendar.component(.hour, from: now) >= 18,
              day != lastPromptDay,
              !store.hasEntry(on: now) else { return }
        lastPromptDay = day
        beginCalling()
    }

    private func beginCalling() {
        guard bubbleWindow == nil else { return }
        let rabbits = rabbitWindows()
        guard let index = rabbits.indices.randomElement(), let screen = rabbits[index].screen ?? NSScreen.main else { return }
        callingIndex = index
        onCallingChanged(index)
        let size = NSSize(width: 225, height: 75)
        var origin = NSPoint(x: rabbits[index].frame.midX - 45, y: rabbits[index].frame.maxY - 5)
        origin.x = min(max(origin.x, screen.visibleFrame.minX + 6), screen.visibleFrame.maxX - size.width - 6)
        let window = NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.level = .floating; window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        let view = DiaryCallBubbleView(frame: NSRect(origin: .zero, size: size))
        view.onClick = { [weak self] in self?.openInput() }
        window.contentView = view
        window.orderFrontRegardless()
        bubbleWindow = window
    }

    private func openInput() {
        if inputController == nil {
            inputController = DiaryInputController { [weak self] text in self?.save(text) }
        }
        inputController?.show()
    }

    private func save(_ text: String) {
        let returningRabbit = ExpeditionPersistence.status == .away
        do {
            try store.save(text)
        } catch {
            onWeeklyMessage("日記を保存できなかったみたい…")
            return
        }
        bubbleWindow?.orderOut(nil); bubbleWindow = nil
        onCallingChanged(nil)
        if let callingIndex { onReward(callingIndex) }
        self.callingIndex = nil
        if returningRabbit {
            ExpeditionPersistence.set(.returning, rabbitIndex: ExpeditionPersistence.rabbitIndex)
            onReturn()
        } else {
            rocketView?.progress = store.rocketProgress()
            if store.rocketProgress() == RocketSchedule.completionDays,
               ExpeditionPersistence.status == .home {
                onWeeklyMessage("ラジャー！ 月までいってくるね！")
                onDeparture()
            }
        }
        showWeeklyReviewIfReady()
    }

    private func showWeeklyReviewIfReady() {
        guard testState == .inactive,
              let batch = store.completedWeeklyBatch(),
              UserDefaults.standard.string(forKey: Self.lastWeeklyReviewKey) != batch.id else { return }
        weeklyReviewController = WeeklyReviewController(entries: batch.entries)
        weeklyReviewController?.show()
        UserDefaults.standard.set(batch.id, forKey: Self.lastWeeklyReviewKey)
    }

    private func showRocket() {
        guard let screen = NSScreen.main,
              let atlas = loadImage(named: "rocket-construction-atlas"),
              let explosionAtlas = loadImage(named: "pixel-explosion-atlas") else { return }
        let size = NSSize(width: 126, height: 220)
        let origin = NSPoint(x: screen.visibleFrame.maxX - size.width - 12, y: screen.visibleFrame.minY + 10)
        let window = NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true; window.isReleasedWhenClosed = false
        let view = RocketView(atlas: atlas, frame: NSRect(origin: .zero, size: size))
        view.progress = store.rocketProgress()
        window.contentView = view
        if ExpeditionPersistence.status == .away || ExpeditionPersistence.status == .returning {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
        rocketView = view; rocketWindow = window
        rocketHomeOrigin = origin

        let flightSize = NSSize(width: 280, height: 280)
        let flight = NSWindow(contentRect: NSRect(origin: .zero, size: flightSize), styleMask: .borderless, backing: .buffered, defer: false)
        flight.isOpaque = false; flight.backgroundColor = .clear; flight.hasShadow = false
        flight.level = window.level
        flight.collectionBehavior = window.collectionBehavior
        flight.ignoresMouseEvents = true; flight.isReleasedWhenClosed = false
        let flightContent = RocketFlightView(
            atlas: atlas,
            explosionAtlas: explosionAtlas,
            frame: NSRect(origin: .zero, size: flightSize)
        )
        flight.contentView = flightContent
        flight.orderOut(nil)
        flightWindow = flight
        flightView = flightContent
    }

    func launchRocket(completion: @escaping () -> Void = {}) {
        guard let screen = NSScreen.main, let window = rocketWindow, let view = rocketView,
              let flightWindow, let flightView, let home = rocketHomeOrigin else {
            completion()
            return
        }
        showMoon(on: screen)
        expeditionTimer?.invalidate()
        launchCompletion = completion
        view.progress = RocketSchedule.completionDays
        view.showsRocket = false
        window.setFrameOrigin(home)
        window.orderFrontRegardless()
        let start = rocketCenter(at: home)
        let target = moonWindow.map { NSPoint(x: $0.frame.midX, y: $0.frame.midY) }
            ?? NSPoint(x: screen.visibleFrame.midX + 140, y: screen.visibleFrame.maxY - 63)
        flightView.mode = .flight
        flightView.scale = 1
        flightView.rotationDegrees = pointingAngle(from: start, to: target)
        setFlightCenter(start, window: flightWindow)
        flightWindow.orderFrontRegardless()
        let started = ProcessInfo.processInfo.systemUptime
        expeditionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickLaunch(startedAt: started, start: start, target: target)
            }
        }
    }

    func returnRocket(completion: @escaping () -> Void) {
        guard let screen = NSScreen.main, let window = rocketWindow, let view = rocketView,
              let flightWindow, let flightView,
              let home = rocketHomeOrigin else { completion(); return }
        showMoon(on: screen)
        expeditionTimer?.invalidate()
        view.progress = RocketSchedule.completionDays
        view.showsRocket = false
        window.orderOut(nil)
        let start = moonWindow.map { NSPoint(x: $0.frame.midX, y: $0.frame.midY) }
            ?? NSPoint(x: screen.visibleFrame.midX + 140, y: screen.visibleFrame.maxY - 63)
        let target = rocketCenter(at: home)
        flightView.mode = .flight
        flightView.scale = 0.18
        flightView.rotationDegrees = pointingAngle(from: start, to: target)
        setFlightCenter(start, window: flightWindow)
        flightWindow.orderFrontRegardless()
        returnCompletion = completion
        let started = ProcessInfo.processInfo.systemUptime
        expeditionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickReturn(startedAt: started, start: start, target: target)
            }
        }
    }

    func finishExpeditionReturn() {
        ExpeditionPersistence.set(.home, rabbitIndex: nil)
        flightWindow?.orderOut(nil)
        rocketView?.showsRocket = true
        rocketView?.progress = store.rocketProgress()
        if let home = rocketHomeOrigin {
            rocketWindow?.setFrameOrigin(home)
            rocketWindow?.orderFrontRegardless()
        }
    }

    func beginTestMode() {
        expeditionTimer?.invalidate()
        expeditionTimer = nil
        launchCompletion = nil
        returnCompletion = nil
        flightWindow?.orderOut(nil)
        moonWindow?.orderOut(nil)
        testState = .building(0)
        rocketView?.isTestMode = true
        rocketView?.showsRocket = true
        rocketView?.progress = 0
        if let home = rocketHomeOrigin {
            rocketWindow?.setFrameOrigin(home)
            rocketWindow?.orderFrontRegardless()
        }
    }

    func advanceTestDay() -> TestAction {
        switch testState {
        case let .building(progress):
            let next = min(progress + 1, RocketSchedule.completionDays)
            rocketView?.showsRocket = true
            rocketView?.progress = next
            if next == RocketSchedule.completionDays {
                testState = .departing
                return .depart
            }
            testState = .building(next)
            return .none
        case .away:
            testState = .returning
            return .returnHome
        case .inactive, .departing, .returning, .finished:
            return .none
        }
    }

    func finishTestReturn() {
        testState = .finished
        flightWindow?.orderOut(nil)
        rocketView?.isTestMode = true
        rocketView?.showsRocket = true
        rocketView?.progress = 0
        if let home = rocketHomeOrigin {
            rocketWindow?.setFrameOrigin(home)
            rocketWindow?.orderFrontRegardless()
        }
    }

    func endTestMode() {
        expeditionTimer?.invalidate()
        expeditionTimer = nil
        launchCompletion = nil
        returnCompletion = nil
        flightWindow?.orderOut(nil)
        moonWindow?.orderOut(nil)
        testState = .inactive
        rocketView?.isTestMode = false
        rocketView?.showsRocket = true
        rocketView?.progress = store.rocketProgress()
        if let home = rocketHomeOrigin {
            rocketWindow?.setFrameOrigin(home)
            if ExpeditionPersistence.status == .away || ExpeditionPersistence.status == .returning {
                rocketWindow?.orderOut(nil)
            } else {
                rocketWindow?.orderFrontRegardless()
            }
        }
    }

    private func tickLaunch(startedAt: TimeInterval, start: NSPoint, target: NSPoint) {
        guard let flightWindow, let flightView else {
            expeditionTimer?.invalidate(); return
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let t = min(max(elapsed / 5.5, 0), 1)
        let eased = 1 - pow(1 - t, 2)
        let center = NSPoint(
            x: start.x + (target.x - start.x) * eased + sin(elapsed * 8) * 2,
            y: start.y + (target.y - start.y) * eased
        )
        setFlightCenter(center, window: flightWindow)
        flightView.scale = 1 - 0.82 * eased
        if t >= 1 {
            expeditionTimer?.invalidate()
            flightWindow.orderOut(nil)
            rocketWindow?.orderOut(nil)
            moonWindow?.orderOut(nil)
            if testState == .departing {
                testState = .away
            } else {
                ExpeditionPersistence.set(.away, rabbitIndex: ExpeditionPersistence.rabbitIndex)
            }
            let completion = launchCompletion
            launchCompletion = nil
            completion?()
        }
    }

    private func tickReturn(startedAt: TimeInterval, start: NSPoint, target: NSPoint) {
        guard let flightWindow, let flightView else {
            expeditionTimer?.invalidate()
            let completion = returnCompletion; returnCompletion = nil; completion?()
            return
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let t = min(max(elapsed / 4.5, 0), 1)
        let eased = t * t
        let center = NSPoint(
            x: start.x + (target.x - start.x) * eased + sin(elapsed * 13) * (2 + 9 * t),
            y: start.y + (target.y - start.y) * eased
        )
        setFlightCenter(center, window: flightWindow)
        flightView.scale = 0.18 + 0.82 * eased
        if t >= 1 {
            expeditionTimer?.invalidate()
            moonWindow?.orderOut(nil)
            explodeRocket()
        }
    }

    private func explodeRocket() {
        guard let view = flightView else {
            let completion = returnCompletion; returnCompletion = nil; completion?(); return
        }
        view.mode = .explosion
        view.explosionProgress = 0
        let started = ProcessInfo.processInfo.systemUptime
        expeditionTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickExplosion(startedAt: started)
            }
        }
    }

    private func tickExplosion(startedAt: TimeInterval) {
        guard let flightView else {
            expeditionTimer?.invalidate()
            let completion = returnCompletion; returnCompletion = nil; completion?(); return
        }
        let t = min(max((ProcessInfo.processInfo.systemUptime - startedAt) / 1.8, 0), 1)
        flightView.explosionProgress = t
        if t >= 1 {
            expeditionTimer?.invalidate()
            flightWindow?.orderOut(nil)
            let completion = returnCompletion
            returnCompletion = nil
            completion?()
        }
    }

    private func rocketCenter(at origin: NSPoint) -> NSPoint {
        NSPoint(x: origin.x + 63, y: origin.y + 123)
    }

    private func setFlightCenter(_ center: NSPoint, window: NSWindow) {
        window.setFrameOrigin(NSPoint(
            x: center.x - window.frame.width / 2,
            y: center.y - window.frame.height / 2
        ))
    }

    private func pointingAngle(from start: NSPoint, to target: NSPoint) -> CGFloat {
        atan2(-(target.x - start.x), target.y - start.y) * 180 / .pi
    }

    private func showMoon(on screen: NSScreen) {
        if moonWindow == nil {
            guard let image = loadImage(named: "pixel-moon-detailed") else { return }
            let size = NSSize(width: 144, height: 144)
            let origin = NSPoint(x: screen.visibleFrame.midX + 95, y: screen.visibleFrame.maxY - size.height - 18)
            let window = NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true; window.isReleasedWhenClosed = false
            window.contentView = MoonView(image: image, frame: NSRect(origin: .zero, size: size))
            moonWindow = window
        }
        moonWindow?.orderFrontRegardless()
    }

    private func loadImage(named name: String) -> NSImage? {
        let packagedURL = Bundle.main.resourceURL?
            .appendingPathComponent("RabbitDesktopPet_RabbitDesktopPet.bundle")
            .appendingPathComponent(name)
            .appendingPathExtension("png")
        let url = packagedURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? Bundle.module.url(forResource: name, withExtension: "png")
        return url.flatMap(NSImage.init(contentsOf:))
    }

    private static let lastWeeklyReviewKey = "diary.last-weekly-review-id"

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }()
}
