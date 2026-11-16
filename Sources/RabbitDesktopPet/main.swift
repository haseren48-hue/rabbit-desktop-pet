import AppKit

private enum RabbitBehavior: CaseIterable {
    case walking
    case carrot
    case washing
    case sleeping
    case codexWorking
    case petting
    case diaryCalling
    case astronaut
    case charredRecovery
}

private enum SleepStyle {
    case prone
    case sideFlop
}

private enum PettingStyle {
    case seated
    case allFours
}

private struct RabbitState {
    var x: CGFloat
    var speed: CGFloat
    var phase: CGFloat
    var behavior: RabbitBehavior
    var behaviorStartedAt: TimeInterval
    var behaviorUntil: TimeInterval
    var sleepStyle: SleepStyle
}

private enum ExpeditionAnimation {
    case none
    case approaching(index: Int, startedAt: TimeInterval, originX: CGFloat, targetX: CGFloat, duration: TimeInterval)
    case saluting(index: Int, startedAt: TimeInterval)
    case boarding(index: Int, startedAt: TimeInterval, originX: CGFloat)
    case charredRecovery(index: Int, startedAt: TimeInterval)
}

private final class RabbitView: NSView {
    let atlases: [RabbitBehavior: NSImage]
    let atlasRow: Int
    var facingRight = true
    var behavior: RabbitBehavior = .walking
    var phase: CGFloat = 0
    var behaviorElapsed: TimeInterval = 0
    var behaviorRemaining: TimeInterval = .infinity
    var sleepStyle: SleepStyle = .prone
    var pettingStyle: PettingStyle = .seated
    var astronautWalking = false
    var onClick: (() -> Void)?

    init(atlases: [RabbitBehavior: NSImage], row: Int) {
        self.atlases = atlases
        self.atlasRow = row
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func resetCursorRects() {
        addCursorRect(bounds.insetBy(dx: 12, dy: 8), cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .none
        // The walking source has more transparent padding than the action atlases.
        // Enlarge only that row so changing actions does not make the rabbit pop in size.
        let baseRect = bounds.insetBy(dx: 4, dy: 3)
        var drawRect: NSRect
        if behavior == .walking || behavior == .carrot {
            let scale: CGFloat = behavior == .walking ? 1.18 : 0.8
            drawRect = NSRect(
                x: baseRect.midX - baseRect.width * scale / 2,
                y: baseRect.minY,
                width: baseRect.width * scale,
                height: baseRect.height * scale
            )
        } else {
            drawRect = baseRect
        }
        if behavior == .astronaut, astronautWalking {
            drawRect.origin.y += abs(sin(phase * .pi)) * 3
        }

        NSGraphicsContext.saveGraphicsState()
        if facingRight {
            drawRabbit(in: drawRect)
        } else {
            let transform = NSAffineTransform()
            transform.translateX(by: bounds.width, yBy: 0)
            transform.scaleX(by: -1, yBy: 1)
            transform.concat()
            drawRabbit(in: drawRect)
        }
        NSGraphicsContext.restoreGraphicsState()


        if behavior == .sleeping, behaviorElapsed >= 4.2, behaviorRemaining > 8.0 {
            drawSleepEffect()
        }
        if behavior == .charredRecovery, behaviorElapsed < 5.2 {
            drawSootEffect()
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawRabbit(in rect: NSRect) {
        guard let atlas = atlases[behavior] ?? atlases[.walking] else { return }
        let columns = 7
        let rows = 6
        let cellWidth = atlas.size.width / CGFloat(columns)
        let cellHeight = atlas.size.height / CGFloat(rows)
        let frame: Int
        if behavior == .petting {
            let seatedFrames = [0, 1, 2, 3, 2, 1]
            let allFoursFrames = [4, 5, 6, 5]
            let frames = pettingStyle == .seated ? seatedFrames : allFoursFrames
            frame = frames[Int(phase) % frames.count]
        } else if behavior == .sleeping {
            if behaviorRemaining <= 8.0 {
                // Wake-up sequence: stop the Zs, roll/rise, then remain drowsy
                // for a while before allowing the next behavior to begin.
                switch behaviorRemaining {
                case 7.0...:
                    frame = sleepStyle == .prone ? 4 : 5
                case 6.0...:
                    frame = sleepStyle == .prone ? 3 : 4
                default:
                    frame = 2 + (Int((6.0 - behaviorRemaining) * 1.5) % 2)
                }
            } else {
                switch behaviorElapsed {
                case ..<1.8:
                    frame = Int(behaviorElapsed * 4) % 2
                case ..<3.8:
                    frame = 2 + (Int((behaviorElapsed - 1.8) * 2.5) % 2)
                case ..<4.5:
                    frame = sleepStyle == .prone ? 4 : 5
                default:
                    frame = sleepStyle == .prone ? 4 : 6
                }
            }
        } else if behavior == .walking {
            // Skip the two squinting poses; walking rabbits should keep their eyes open.
            let openEyeFrames = [0, 2, 3, 5, 6, 3]
            frame = openEyeFrames[Int(phase) % openEyeFrames.count]
        } else if behavior == .astronaut {
            let frames = astronautWalking ? [0, 6, 0, 6] : [1, 2, 1, 5]
            frame = frames[Int(phase) % frames.count]
        } else {
            frame = Int(phase) % columns
        }
        // NSImage source coordinates start at the bottom, while atlas rows are top-down.
        let sourceRow = rows - 1 - atlasRow
        let source = NSRect(
            x: CGFloat(frame) * cellWidth,
            y: CGFloat(sourceRow) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        atlas.draw(in: rect, from: source, operation: .sourceOver, fraction: 1)
    }

    private func drawSleepEffect() {
        let pulse = 0.72 + 0.22 * sin(CGFloat(behaviorElapsed) * 2.2)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.52, green: 0.66, blue: 0.92, alpha: pulse),
            .strokeColor: NSColor.white.withAlphaComponent(pulse * 0.8),
            .strokeWidth: -2.0,
        ]
        NSAttributedString(string: "zzz…", attributes: attributes).draw(
            at: NSPoint(x: bounds.midX + 12, y: bounds.midY + 15)
        )
    }

    private func drawSootEffect() {
        let progress = CGFloat(min(max(behaviorElapsed / 5.2, 0), 1))
        let count = max(0, 10 - Int(progress * 9))
        for index in 0..<count {
            let seed = CGFloat(index * 37 + atlasRow * 19)
            let x = bounds.midX + sin(seed) * 39
            let fall = CGFloat(behaviorElapsed * 22) + CGFloat(index * 13)
            let y = bounds.midY + 28 - fall.truncatingRemainder(dividingBy: 82)
            let size = CGFloat(2 + index % 3)
            NSColor(calibratedWhite: 0.08 + CGFloat(index % 3) * 0.05, alpha: 0.75).setFill()
            NSBezierPath(rect: NSRect(x: x, y: y, width: size, height: size)).fill()
        }
    }
}

@MainActor
private final class RabbitController: NSObject {
    private let names = ["cream", "white_black", "gray_white", "spotted", "chestnut", "silver"]
    private var windows: [NSWindow] = []
    private var views: [RabbitView] = []
    private var states: [RabbitState] = []
    private var timer: Timer?
    private var notificationPresenter: RabbitNotificationPresenter?
    private var notificationMonitor: ExternalNotificationMonitor?
    private var codexTaskMonitor: CodexTaskMonitor?
    private var codexWorkerIndex: Int?
    private var diaryCallerIndex: Int?
    private var diaryCoordinator: DiaryCoordinator?
    private var expeditionAnimation: ExpeditionAnimation = .none
    private var expeditionIsTest = false
    private var testRabbitIndex: Int?
    private var testPreferredRabbitIndex: Int?
    private var testAutoTimer: Timer?
    private var testAutoObservedState: DiaryCoordinator.TestState?
    private var testAutoNextStepAt: TimeInterval = 0
    private var farewellRabbitIndices: Set<Int> = []
    private var pettingUntil: [TimeInterval] = []
    private var pettingStyles: [PettingStyle] = []
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private let petSize = NSSize(width: 140, height: 140)

    private func floorY(on screen: NSScreen) -> CGFloat {
        // Keep the rabbits above a bottom-positioned Dock even when it auto-hides.
        max(screen.visibleFrame.minY + 8, screen.frame.minY + 116)
    }

    func start() {
        guard let screen = NSScreen.main else { return }
        let atlasNames: [RabbitBehavior: String] = [
            .walking: "rabbit-hop-atlas",
            .carrot: "rabbit-carrot-atlas",
            .washing: "rabbit-washing-atlas",
            .sleeping: "rabbit-sleeping-atlas-v2",
            .codexWorking: "rabbit-codex-working-atlas",
            .petting: "rabbit-petting-atlas",
            .diaryCalling: "rabbit-diary-calling-atlas",
            .astronaut: "rabbit-astronaut-atlas",
            .charredRecovery: "rabbit-charred-recovery-atlas",
        ]
        var atlases: [RabbitBehavior: NSImage] = [:]
        let packagedResources = Bundle.main.resourceURL?
            .appendingPathComponent("RabbitDesktopPet_RabbitDesktopPet.bundle")
        for (behavior, name) in atlasNames {
            let packagedURL = packagedResources?
                .appendingPathComponent(name)
                .appendingPathExtension("png")
            let url = packagedURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                ?? Bundle.module.url(forResource: name, withExtension: "png")
            guard let url,
                  let image = NSImage(contentsOf: url) else { return }
            atlases[behavior] = image
        }
        let floor = floorY(on: screen)

        for index in names.indices {
            let startX = screen.visibleFrame.minX + 30 + CGFloat(index) *
                max(125, (screen.visibleFrame.width - 180) / CGFloat(names.count))
            let frame = NSRect(x: startX, y: floor, width: petSize.width, height: petSize.height)
            let window = NSWindow(
                contentRect: frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            // Keep pets above Finder's clickable desktop/icons, but below every
            // normal application window. This preserves both visibility and clicks.
            window.level = NSWindow.Level(
                rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
            )
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.isReleasedWhenClosed = false

            let initialBehavior: RabbitBehavior = [
                .sleeping, .carrot, .washing, .sleeping, .walking, .carrot,
            ][index]
            let initialSpeed = index.isMultiple(of: 2)
                ? CGFloat.random(in: 18...31)
                : CGFloat.random(in: -31 ... -18)
            let initialPhase = CGFloat.random(in: 0 ... (.pi * 2))
            let initialSleepStyle: SleepStyle = Bool.random() ? .prone : .sideFlop
            let startedAt = ProcessInfo.processInfo.systemUptime
            let initialDuration = initialBehavior == .sleeping
                ? Double.random(in: 40...64)
                : Double.random(in: 10...18)

            let rabbitView = RabbitView(atlases: atlases, row: index)
            rabbitView.behavior = initialBehavior
            rabbitView.phase = initialPhase
            rabbitView.facingRight = initialSpeed > 0
            rabbitView.behaviorElapsed = 0
            rabbitView.behaviorRemaining = initialDuration
            rabbitView.sleepStyle = initialSleepStyle
            rabbitView.onClick = { [weak self] in self?.beginPetting(index: index) }
            window.contentView = rabbitView
            window.orderFrontRegardless()

            windows.append(window)
            views.append(rabbitView)
            states.append(RabbitState(
                x: startX,
                speed: initialSpeed,
                phase: initialPhase,
                behavior: initialBehavior,
                behaviorStartedAt: startedAt,
                behaviorUntil: startedAt + initialDuration,
                sleepStyle: initialSleepStyle
            ))
            pettingUntil.append(0)
            pettingStyles.append(.seated)
        }

        timer = Timer.scheduledTimer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)

        let presenter = RabbitNotificationPresenter { [weak self] in self?.windows ?? [] }
        let monitor = ExternalNotificationMonitor { [weak presenter] notification in
            presenter?.enqueue(notification)
        }
        notificationPresenter = presenter
        notificationMonitor = monitor
        monitor.start()

        let codexMonitor = CodexTaskMonitor(
            onWorkingChanged: { [weak self] working in self?.setCodexWorking(working) }
        )
        codexTaskMonitor = codexMonitor
        codexMonitor.start()

        let diary = DiaryCoordinator(
            rabbitWindows: { [weak self] in self?.windows ?? [] },
            onCallingChanged: { [weak self] index in self?.diaryCallerIndex = index },
            onReward: { [weak self] index in self?.showDiaryReward(index: index) },
            onWeeklyMessage: { [weak presenter] message in presenter?.showDiaryMessage(message) },
            onDeparture: { [weak self] in self?.beginExpeditionDeparture() },
            onReturn: { [weak self] in self?.beginExpeditionReturn() }
        )
        diaryCoordinator = diary
        diary.start()
        restorePersistedExpedition()
    }

    func requestNotificationAccess() { notificationMonitor?.requestPermissionAgain() }

    func showTestNotification() { notificationPresenter?.showTestNotification() }

    func dismissAllNotifications() { notificationPresenter?.dismissAll() }

    func showDiaryNow() { diaryCoordinator?.showDiaryNow() }

    func startSequenceTest() {
        guard ExpeditionPersistence.status == .home else { return }
        testAutoTimer?.invalidate()
        testAutoTimer = nil
        expeditionAnimation = .none
        farewellRabbitIndices.removeAll()
        expeditionIsTest = true
        testRabbitIndex = nil
        testPreferredRabbitIndex = nil
        for window in windows { window.orderFrontRegardless() }
        diaryCoordinator?.beginTestMode()
    }

    func advanceSequenceTestDay() {
        if !expeditionIsTest {
            startSequenceTest()
        }
        guard expeditionIsTest, let diaryCoordinator else { return }
        switch diaryCoordinator.advanceTestDay() {
        case .none:
            break
        case .depart:
            beginExpeditionDeparture(index: testPreferredRabbitIndex, isTest: true)
        case .returnHome:
            beginExpeditionReturn(isTest: true)
        }
    }

    func runSequenceTestAutomatically(preferredRabbitIndex: Int? = nil) {
        startSequenceTest()
        testPreferredRabbitIndex = preferredRabbitIndex
        guard expeditionIsTest, let state = diaryCoordinator?.testState else { return }
        testAutoObservedState = state
        testAutoNextStepAt = ProcessInfo.processInfo.systemUptime + 0.8
        testAutoTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickAutomaticSequenceTest() }
        }
    }

    func stopSequenceTest() {
        guard expeditionIsTest else { return }
        testAutoTimer?.invalidate()
        testAutoTimer = nil
        testAutoObservedState = nil
        expeditionAnimation = .none
        farewellRabbitIndices.removeAll()
        expeditionIsTest = false
        testRabbitIndex = nil
        testPreferredRabbitIndex = nil
        for window in windows { window.orderFrontRegardless() }
        diaryCoordinator?.endTestMode()
    }

    private func tickAutomaticSequenceTest() {
        guard expeditionIsTest, let state = diaryCoordinator?.testState else {
            testAutoTimer?.invalidate()
            testAutoTimer = nil
            return
        }
        if state == .finished {
            testAutoTimer?.invalidate()
            testAutoTimer = nil
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if testAutoObservedState != state {
            testAutoObservedState = state
            testAutoNextStepAt = now + (state == .away ? 1.2 : 0.72)
            return
        }
        guard now >= testAutoNextStepAt else { return }
        switch state {
        case .building, .away:
            advanceSequenceTestDay()
        case .inactive, .departing, .returning, .finished:
            break
        }
        testAutoObservedState = diaryCoordinator?.testState
        testAutoNextStepAt = now + 0.72
    }

    private func setCodexWorking(_ working: Bool) {
        codexWorkerIndex = working ? windows.indices.randomElement() : nil
    }

    private func beginPetting(index: Int) {
        guard pettingUntil.indices.contains(index) else { return }
        pettingUntil[index] = ProcessInfo.processInfo.systemUptime + 8
        pettingStyles[index] = Bool.random() ? .seated : .allFours
        states[index].phase = 0
    }

    private func showDiaryReward(index: Int) {
        guard states.indices.contains(index) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        states[index].behavior = .carrot
        states[index].behaviorStartedAt = now
        states[index].behaviorUntil = now + 12
        states[index].phase = 0
    }

    @objc private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        updateExpeditionAnimation(now: now)

        for index in states.indices {
            guard let screen = windows[index].screen ?? NSScreen.main else { continue }
            var state = states[index]
            let minX = screen.visibleFrame.minX
            let maxX = screen.visibleFrame.maxX - petSize.width

            if now >= state.behaviorUntil {
                chooseNextBehavior(for: index, now: now)
                state = states[index]
            }

            let isCodexWorker = index == codexWorkerIndex
            let isBeingPetted = now < pettingUntil[index]
            let isExpeditionRabbit = expeditionBehavior(for: index) != nil
            if state.behavior == .walking, !isCodexWorker, !isBeingPetted, !isExpeditionRabbit,
               !farewellRabbitIndices.contains(index) {
                state.x += state.speed * dt
                if state.x <= minX || state.x >= maxX {
                    state.x = min(max(state.x, minX), maxX)
                    state.speed *= -1
                }
            }

            let phaseSpeed: CGFloat
            let displayedBehavior: RabbitBehavior
            if let expeditionBehavior = expeditionBehavior(for: index) {
                displayedBehavior = expeditionBehavior
            } else if farewellRabbitIndices.contains(index) {
                displayedBehavior = .diaryCalling
            } else if isBeingPetted {
                displayedBehavior = .petting
            } else if index == diaryCallerIndex {
                displayedBehavior = .diaryCalling
            } else if isCodexWorker {
                displayedBehavior = .codexWorking
            } else {
                displayedBehavior = state.behavior
            }
            switch displayedBehavior {
            case .walking: phaseSpeed = 10
            case .carrot: phaseSpeed = 6
            case .washing: phaseSpeed = 7
            case .sleeping: phaseSpeed = 3.5
            case .codexWorking: phaseSpeed = 8
            case .petting: phaseSpeed = 5
            case .diaryCalling: phaseSpeed = 4
            case .astronaut: phaseSpeed = 2.6
            case .charredRecovery: phaseSpeed = 0
            }
            state.phase += CGFloat(dt) * phaseSpeed
            views[index].facingRight = expeditionFacesRight(index: index) ?? (state.speed > 0)
            views[index].behavior = displayedBehavior
            views[index].astronautWalking = astronautIsWalking(index: index)
            if case let .charredRecovery(charredIndex, startedAt) = expeditionAnimation,
               charredIndex == index {
                views[index].phase = min(6, CGFloat(Int((now - startedAt) * 1.15)))
            } else {
                views[index].phase = state.phase
            }
            if case let .charredRecovery(charredIndex, startedAt) = expeditionAnimation,
               charredIndex == index {
                views[index].behaviorElapsed = now - startedAt
            } else if case let .saluting(selected, startedAt) = expeditionAnimation,
                      selected == index {
                views[index].behaviorElapsed = now - startedAt
            } else if case let .approaching(selected, startedAt, _, _, _) = expeditionAnimation,
                      selected == index {
                views[index].behaviorElapsed = now - startedAt
            } else if case let .boarding(selected, startedAt, _) = expeditionAnimation,
                      selected == index {
                views[index].behaviorElapsed = now - startedAt
            } else {
                views[index].behaviorElapsed = now - state.behaviorStartedAt
            }
            views[index].behaviorRemaining = max(0, state.behaviorUntil - now)
            views[index].sleepStyle = state.sleepStyle
            views[index].pettingStyle = pettingStyles[index]
            views[index].needsDisplay = true
            windows[index].setFrameOrigin(NSPoint(x: state.x, y: floorY(on: screen)))
            states[index] = state
        }
    }

    private func chooseNextBehavior(for index: Int, now: TimeInterval) {
        guard states[index].behaviorUntil <= now else { return }

        let next: RabbitBehavior
        if states[index].behavior != .sleeping, Int.random(in: 0..<7) == 0 {
            // 1/7 is exactly one third of the previous 3/7 sleep selection rate.
            next = .sleeping
        } else {
            var nonSleepChoices: [RabbitBehavior] = [
                .walking, .walking, .walking, .carrot, .carrot, .washing,
            ]
            nonSleepChoices.removeAll { $0 == states[index].behavior }
            next = nonSleepChoices.randomElement() ?? .walking
        }
        states[index].behavior = next
        states[index].behaviorStartedAt = now
        if next == .sleeping {
            states[index].sleepStyle = Bool.random() ? .prone : .sideFlop
        }
        let duration: ClosedRange<Double>
        switch next {
        case .walking: duration = 10...20
        case .carrot: duration = 10...16
        case .washing: duration = 8...14
        case .sleeping: duration = 40...64
        case .codexWorking: duration = 10...20
        case .petting: duration = 8...8
        case .diaryCalling: duration = 10...20
        case .astronaut: duration = 10...20
        case .charredRecovery: duration = 10...20
        }
        states[index].behaviorUntil = now + Double.random(in: duration)
    }

    private func expeditionBehavior(for index: Int) -> RabbitBehavior? {
        switch expeditionAnimation {
        case let .approaching(selected, _, _, _, _) where selected == index:
            return .astronaut
        case let .saluting(selected, _) where selected == index:
            return .astronaut
        case let .boarding(selected, _, _) where selected == index:
            return .astronaut
        case let .charredRecovery(selected, _) where selected == index:
            return .charredRecovery
        default:
            return nil
        }
    }

    private func astronautIsWalking(index: Int) -> Bool {
        switch expeditionAnimation {
        case let .approaching(selected, _, _, _, _) where selected == index,
             let .boarding(selected, _, _) where selected == index:
            return true
        default:
            return false
        }
    }

    private func expeditionFacesRight(index: Int) -> Bool? {
        switch expeditionAnimation {
        case let .approaching(selected, _, _, _, _) where selected == index,
             let .boarding(selected, _, _) where selected == index:
            return true
        default:
            return nil
        }
    }

    private func rabbitNearestToRocket(excluding excluded: Int?) -> Int? {
        guard let screen = NSScreen.main else { return nil }
        let rocketLeft = screen.visibleFrame.maxX - 126 - 12
        return windows.indices
            .filter { $0 != excluded && windows[$0].isVisible }
            .min { first, second in
                abs(windows[first].frame.maxX - rocketLeft) < abs(windows[second].frame.maxX - rocketLeft)
            }
    }

    private func beginExpeditionDeparture(index preferredIndex: Int? = nil, isTest: Bool = false) {
        guard case .none = expeditionAnimation else { return }
        let index = preferredIndex ?? rabbitNearestToRocket(excluding: diaryCallerIndex)
        guard let index, windows.indices.contains(index), let screen = windows[index].screen ?? NSScreen.main else { return }
        if isTest {
            expeditionIsTest = true
            testRabbitIndex = index
        } else {
            ExpeditionPersistence.set(.departing, rabbitIndex: index)
        }
        windows[index].orderFrontRegardless()
        states[index].phase = 0
        states[index].speed = abs(states[index].speed)
        let originX = states[index].x
        let targetX = screen.visibleFrame.maxX - 126 - 12 - petSize.width + 18
        let duration = min(6.0, max(1.2, TimeInterval(abs(targetX - originX) / 90)))
        expeditionAnimation = .approaching(
            index: index,
            startedAt: ProcessInfo.processInfo.systemUptime,
            originX: originX,
            targetX: targetX,
            duration: duration
        )
    }

    private func beginExpeditionReturn(isTest: Bool = false) {
        let returningIndex = isTest ? testRabbitIndex : ExpeditionPersistence.rabbitIndex
        guard case .none = expeditionAnimation,
              let index = returningIndex,
              windows.indices.contains(index) else { return }
        if isTest {
            expeditionIsTest = true
        } else {
            ExpeditionPersistence.set(.returning, rabbitIndex: index)
        }
        windows[index].orderOut(nil)
        diaryCoordinator?.returnRocket { [weak self] in
            self?.beginCharredRecovery(index: index)
        }
    }

    private func beginCharredRecovery(index: Int) {
        guard windows.indices.contains(index), let screen = NSScreen.main else { return }
        let x = screen.visibleFrame.maxX - petSize.width - 24
        states[index].x = x
        states[index].phase = 0
        windows[index].setFrameOrigin(NSPoint(x: x, y: floorY(on: screen)))
        windows[index].orderFrontRegardless()
        expeditionAnimation = .charredRecovery(index: index, startedAt: ProcessInfo.processInfo.systemUptime)
    }

    private func updateExpeditionAnimation(now: TimeInterval) {
        switch expeditionAnimation {
        case let .approaching(index, startedAt, originX, targetX, duration):
            let t = min(max((now - startedAt) / duration, 0), 1)
            let eased = t * t * (3 - 2 * t)
            states[index].x = originX + (targetX - originX) * eased
            if t >= 1 {
                states[index].x = targetX
                states[index].phase = 0
                expeditionAnimation = .saluting(index: index, startedAt: now)
            }
        case let .saluting(index, startedAt):
            if now - startedAt >= 3.2 {
                expeditionAnimation = .boarding(index: index, startedAt: now, originX: states[index].x)
            }
        case let .boarding(index, startedAt, originX):
            guard let screen = windows[index].screen ?? NSScreen.main else { return }
            let t = min(max((now - startedAt) / 2.2, 0), 1)
            let eased = t * t * (3 - 2 * t)
            let targetX = screen.visibleFrame.maxX - 126 - 2
            states[index].x = originX + (targetX - originX) * eased
            if t >= 1 {
                windows[index].orderOut(nil)
                if expeditionIsTest {
                    testRabbitIndex = index
                } else {
                    ExpeditionPersistence.set(.away, rabbitIndex: index)
                }
                expeditionAnimation = .none
                farewellRabbitIndices = Set(windows.indices.filter { $0 != index })
                diaryCoordinator?.launchRocket { [weak self] in
                    self?.farewellRabbitIndices.removeAll()
                }
            }
        case let .charredRecovery(index, startedAt):
            if now - startedAt >= 6.5 {
                let next: RabbitBehavior = [.walking, .carrot, .washing].randomElement() ?? .walking
                states[index].behavior = next
                states[index].behaviorStartedAt = now
                states[index].behaviorUntil = now + 12
                states[index].phase = 0
                expeditionAnimation = .none
                if expeditionIsTest {
                    diaryCoordinator?.finishTestReturn()
                } else {
                    diaryCoordinator?.finishExpeditionReturn()
                }
            }
        case .none:
            break
        }
    }

    private func restorePersistedExpedition() {
        guard let index = ExpeditionPersistence.rabbitIndex, windows.indices.contains(index) else { return }
        switch ExpeditionPersistence.status {
        case .home:
            break
        case .departing:
            beginExpeditionDeparture(index: index)
        case .away:
            windows[index].orderOut(nil)
        case .returning:
            windows[index].orderOut(nil)
            DispatchQueue.main.async { [weak self] in self?.beginExpeditionReturn() }
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: RabbitController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = RabbitController()
        controller?.start()

        if CommandLine.arguments.contains("--auto-sequence-test") {
            let preferredRabbitIndex = CommandLine.arguments
                .first { $0.hasPrefix("--auto-sequence-test-rabbit=") }
                .flatMap { Int($0.split(separator: "=").last ?? "") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.controller?.runSequenceTestAutomatically(preferredRabbitIndex: preferredRabbitIndex)
            }
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "🐇"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "通知アクセスを許可", action: #selector(requestNotificationAccess), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "テスト通知を表示", action: #selector(showTestNotification), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "通知をすべて閉じる", action: #selector(dismissAllNotifications), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "今すぐ日記を書く", action: #selector(showDiaryNow), keyEquivalent: "d"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "シーケンステストを開始（0/\(RocketSchedule.completionDays)）",
            action: #selector(startSequenceTest),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(title: "テスト：1日進める", action: #selector(advanceSequenceTestDay), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "テスト：全自動再生", action: #selector(runSequenceTestAutomatically), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "テストモードを終了", action: #selector(stopSequenceTest), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "6匹のウサギを終了", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func requestNotificationAccess() { controller?.requestNotificationAccess() }

    @objc private func showTestNotification() { controller?.showTestNotification() }

    @objc private func dismissAllNotifications() { controller?.dismissAllNotifications() }

    @objc private func showDiaryNow() { controller?.showDiaryNow() }

    @objc private func startSequenceTest() { controller?.startSequenceTest() }

    @objc private func advanceSequenceTestDay() { controller?.advanceSequenceTestDay() }

    @objc private func runSequenceTestAutomatically() { controller?.runSequenceTestAutomatically() }

    @objc private func stopSequenceTest() { controller?.stopSequenceTest() }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
