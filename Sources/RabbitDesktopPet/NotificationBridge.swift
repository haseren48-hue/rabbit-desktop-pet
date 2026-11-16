import AppKit
import ApplicationServices

enum NotificationSource: String {
    case line
    case outlook
    case codex
    case diary

    var bundleIdentifier: String {
        switch self {
        case .line: "jp.naver.line.mac"
        case .outlook: "com.microsoft.Outlook"
        case .codex: "com.openai.codex"
        case .diary: "com.local.RabbitDesktopPet"
        }
    }

    var appNames: [String] {
        switch self {
        case .line: ["LINE"]
        case .outlook: ["Microsoft Outlook", "Outlook"]
        case .codex: ["Codex", "ChatGPT"]
        case .diary: ["日記"]
        }
    }
}

struct RabbitNotification {
    let source: NotificationSource
    let message: String
    let fingerprint: String
}

@MainActor
private final class NotificationBubbleView: NSView {
    var message = ""
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.08, alpha: 0.93).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 9), xRadius: 15, yRadius: 15).fill()

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 30, y: 10))
        tail.line(to: NSPoint(x: 46, y: 0))
        tail.line(to: NSPoint(x: 54, y: 10))
        tail.close()
        tail.fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        NSAttributedString(string: message, attributes: attributes).draw(
            in: NSRect(x: 15, y: 23, width: bounds.width - 50, height: 22)
        )

        let closeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1),
        ]
        NSAttributedString(string: "×", attributes: closeAttributes).draw(
            at: NSPoint(x: bounds.width - 29, y: 23)
        )
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.x >= bounds.width - 42 {
            onClose?()
        } else {
            onOpen?()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

@MainActor
final class RabbitNotificationPresenter {
    private let rabbitWindows: () -> [NSWindow]
    private var queue: [RabbitNotification] = []
    private var current: RabbitNotification?
    private var bubbleWindow: NSWindow?
    private var automaticClose: Timer?

    init(rabbitWindows: @escaping () -> [NSWindow]) {
        self.rabbitWindows = rabbitWindows
    }

    func enqueue(_ notification: RabbitNotification) {
        queue.append(notification)
        showNextIfNeeded()
    }

    func showTestNotification() {
        enqueue(RabbitNotification(
            source: .codex,
            message: "Codexからテストメッセージだよ！",
            fingerprint: UUID().uuidString
        ))
    }

    func showDiaryMessage(_ message: String) {
        enqueue(RabbitNotification(source: .diary, message: message, fingerprint: UUID().uuidString))
    }

    func dismissAll() {
        queue.removeAll()
        automaticClose?.invalidate()
        automaticClose = nil
        bubbleWindow?.orderOut(nil)
        bubbleWindow = nil
        current = nil
    }

    private func showNextIfNeeded() {
        guard current == nil, !queue.isEmpty else { return }
        let notification = queue.removeFirst()
        guard let rabbit = rabbitWindows().randomElement(), let screen = rabbit.screen ?? NSScreen.main else {
            queue.insert(notification, at: 0)
            return
        }

        current = notification
        let size = NSSize(width: 275, height: 78)
        var origin = NSPoint(
            x: rabbit.frame.midX - 45,
            y: rabbit.frame.maxY - 7
        )
        origin.x = min(max(origin.x, screen.visibleFrame.minX + 6), screen.visibleFrame.maxX - size.width - 6)
        origin.y = min(origin.y, screen.visibleFrame.maxY - size.height - 6)

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        // Rabbits stay behind normal windows, but their actionable notification
        // must be above them so the body and close button can receive clicks.
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false

        let view = NotificationBubbleView(frame: NSRect(origin: .zero, size: size))
        view.message = notification.message
        view.onClose = { [weak self] in self?.dismissCurrent() }
        view.onOpen = { [weak self] in self?.openCurrent() }
        window.contentView = view
        window.orderFrontRegardless()
        bubbleWindow = window

        automaticClose?.invalidate()
        automaticClose = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismissCurrent() }
        }
    }

    private func openCurrent() {
        guard let notification = current else { return }
        if let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: notification.source.bundleIdentifier
        ) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        }
        dismissCurrent()
    }

    private func dismissCurrent() {
        automaticClose?.invalidate()
        automaticClose = nil
        bubbleWindow?.orderOut(nil)
        bubbleWindow = nil
        current = nil
        showNextIfNeeded()
    }
}

@MainActor
final class ExternalNotificationMonitor {
    private let onNotification: (RabbitNotification) -> Void
    private var timer: Timer?
    private var seen: Set<String> = []
    private var seenOrder: [String] = []

    init(onNotification: @escaping (RabbitNotification) -> Void) {
        self.onNotification = onNotification
    }

    func start(promptForPermission: Bool = true) {
        timer?.invalidate()
        timer = nil
        let options = [
            "AXTrustedCheckOptionPrompt": promptForPermission,
        ] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            if promptForPermission,
               let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(settingsURL)
            }
            return
        }
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    func requestPermissionAgain() {
        start(promptForPermission: true)
    }

    private func scan() {
        guard AXIsProcessTrusted() else { return }
        let candidates = NSWorkspace.shared.runningApplications.filter { app in
            let id = app.bundleIdentifier?.lowercased() ?? ""
            let name = app.localizedName?.lowercased() ?? ""
            return id.contains("notificationcenter") || name.contains("notificationcenter") ||
                name.contains("notification center")
        }

        for application in candidates {
            let root = AXUIElementCreateApplication(application.processIdentifier)
            inspect(element: root, depth: 0)
        }
    }

    @discardableResult
    private func inspect(element: AXUIElement, depth: Int) -> Bool {
        guard depth < 14 else { return false }
        let children = attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
        var handledDescendant = false
        for child in children {
            handledDescendant = inspect(element: child, depth: depth + 1) || handledDescendant
        }

        guard !handledDescendant else { return true }
        let role = attribute(element, kAXRoleAttribute as String) as? String ?? ""
        guard role == kAXGroupRole as String || role == kAXWindowRole as String else { return false }
        let strings = collectStrings(from: element, depth: 0)
        guard let notification = makeNotification(from: strings) else { return false }
        rememberAndDeliver(notification)
        return true
    }

    private func collectStrings(from element: AXUIElement, depth: Int) -> [String] {
        guard depth < 8 else { return [] }
        var result: [String] = []
        for name in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
            if let value = attribute(element, name as String) as? String {
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty, !result.contains(cleaned) { result.append(cleaned) }
            }
        }
        let children = attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
        for child in children { result.append(contentsOf: collectStrings(from: child, depth: depth + 1)) }
        return result
    }

    private func makeNotification(from strings: [String]) -> RabbitNotification? {
        guard !strings.isEmpty else { return nil }
        let joined = strings.joined(separator: " | ")
        let lowered = joined.lowercased()
        let source: NotificationSource
        if lowered.contains("microsoft outlook") || lowered.contains("outlook") {
            source = .outlook
        } else if strings.contains(where: { $0.caseInsensitiveCompare("LINE") == .orderedSame }) {
            source = .line
        } else {
            return nil
        }

        let ignored = Set(source.appNames.map { $0.lowercased() } + [
            "notification", "notifications", "close", "show", "reply", "options",
        ])
        let sender = strings.first { value in
            let normalized = value.lowercased()
            return !ignored.contains(normalized) && value.count <= 80 &&
                !normalized.contains("notification center")
        }

        let message: String
        switch source {
        case .line:
            message = sender.map { "\($0)からLINEだよ！" } ?? "LINEが届いたよ！"
        case .outlook:
            message = sender.map { "\($0)からメールだよ！" } ?? "新しいメールだよ！"
        case .codex:
            message = "Codexからメッセージだよ！"
        case .diary:
            message = "日記のじかんだよ！"
        }
        return RabbitNotification(source: source, message: message, fingerprint: "\(source.rawValue)|\(joined)")
    }

    private func rememberAndDeliver(_ notification: RabbitNotification) {
        guard !seen.contains(notification.fingerprint) else { return }
        seen.insert(notification.fingerprint)
        seenOrder.append(notification.fingerprint)
        if seenOrder.count > 200 {
            seen.remove(seenOrder.removeFirst())
        }
        onNotification(notification)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
