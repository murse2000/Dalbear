import AppKit
import Carbon
import FolderCore
import QuickLookUI

private struct FolderWorkspace: Codable {
    var id = UUID()
    var title: String
    var bookmark: Data
}

final class FolderHubController: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout, NSMenuDelegate, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    var enabled = UserDefaults.standard.bool(forKey: "folderHubEnabled") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "folderHubEnabled")
            if enabled { start() } else { stop() }
        }
    }
    private var workspaces: [FolderWorkspace] = []
    private var selectedWorkspace: UUID?
    private var locations: [UUID: URL] = [:]
    private var directory: URL?
    private var files: [FolderFile] = []
    private var sort = FolderSort(rawValue: UserDefaults.standard.string(forKey: "folderHubSort") ?? "") ?? .name
    private var listMode = UserDefaults.standard.bool(forKey: "folderHubList")
    private var pinned = UserDefaults.standard.bool(forKey: "folderHubPinned")
    private var panel: FolderHubPanel?
    private let collection = FolderCollectionView()
    private let tabs = NSStackView()
    private let path = NSPathControl()
    private let status = NSTextField(labelWithString: "작업 폴더를 추가해 주세요.")
    private let paw = BearPawView()
    private var pinButton: NSButton?
    private var viewButton: NSButton?
    private var monitors: [Any] = []
    private var hideTask: DispatchWorkItem?
    private var watcher: DispatchSourceFileSystemObject?
    private let fileQueue = DispatchQueue(label: "MouseWheelFix.FolderFiles", qos: .userInitiated)
    private var loadID = UUID()
    private var busy = false
    private var interacting = false
    private var dragging = false
    private var sharingPicker: NSSharingServicePicker?
    private var sharingService: NSSharingService?
    private var previewPanel: NSPanel?
    private var previewView: QLPreviewView?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var shortcutHint = "⌘⌥→ 열기"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "folderHubWorkspaces") {
            workspaces = (try? JSONDecoder().decode([FolderWorkspace].self, from: data)) ?? []
        }
        selectedWorkspace = UserDefaults.standard.string(forKey: "folderHubSelected").flatMap(UUID.init(uuidString:))
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screenChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screenChanged), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func start() {
        guard enabled, monitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in self?.pointerMoved() }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in self?.pointerMoved(); return event }) { monitors.append(monitor) }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<FolderHubController>.fromOpaque(context).takeUnretainedValue().togglePanel()
            return noErr
        }, 1, &type, context, &hotKeyHandler)
        let result = RegisterEventHotKey(UInt32(kVK_RightArrow), UInt32(cmdKey | optionKey), EventHotKeyID(signature: 0x4D574648, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        shortcutHint = result == noErr ? "⌘⌥→ 열기" : "단축키 사용 중 · 메뉴에서 열기"
        status.toolTip = shortcutHint
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        hotKey = nil
        hotKeyHandler = nil
        hide()
    }

    @objc func open() {
        if !enabled { enabled = true }
        show(on: screenAtPointer() ?? NSScreen.main)
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    private func togglePanel() {
        if panel?.isVisible == true { hide() } else { open() }
    }

    private func screenAtPointer() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
    }

    private func trigger(on screen: NSScreen) -> NSRect {
        var width: CGFloat = 150
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            width = right.minX - left.maxX
        }
        return NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - max(screen.safeAreaInsets.top, 8), width: width, height: max(screen.safeAreaInsets.top, 8))
    }

    private func pointerMoved() {
        guard enabled else { return }
        let point = NSEvent.mouseLocation
        if let screen = screenAtPointer(), trigger(on: screen).contains(point) {
            hideTask?.cancel(); hideTask = nil
            if panel?.isVisible != true || (!pinned && panel?.screen?.frame != screen.frame) { show(on: screen) }
            return
        }
        guard let panel, panel.isVisible else { return }
        let inPreview = previewPanel?.isVisible == true
        if panel.frame.insetBy(dx: -4, dy: -6).contains(point) || pinned || interacting || dragging || busy || inPreview || panel.attachedSheet != nil || NSEvent.pressedMouseButtons != 0 {
            hideTask?.cancel(); hideTask = nil
        } else if hideTask == nil {
            let task = DispatchWorkItem { [weak self] in self?.hide() }
            hideTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
        }
    }

    private func show(on screen: NSScreen?) {
        guard let screen else { return }
        if panel == nil { makePanel() }
        guard let panel else { return }
        let size = NSSize(width: min(900, screen.frame.width - 32), height: min(446, screen.frame.height - 80))
        let top = screen.frame.maxY - max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        paw.appear()
        if directory == nil {
            selectWorkspace(selectedWorkspace ?? workspaces.first?.id)
        } else { refresh() }
    }

    private func hide() {
        hideTask?.cancel(); hideTask = nil
        paw.stopMotion()
        panel?.orderOut(nil)
        previewPanel?.orderOut(nil)
        watcher?.cancel(); watcher = nil
        // 비동기 폴더 읽기가 늦게 끝나도 숨긴 창에 감시자를 다시 만들지 않습니다.
        loadID = UUID()
    }

    @objc private func screenChanged() {
        guard panel?.isVisible == true else { return }
        if pinned { show(on: panel?.screen ?? NSScreen.main) } else { hide() }
    }

    private func makePanel() {
        let panel = FolderHubPanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 446), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "폴더 허브"
        panel.setAccessibilityLabel("폴더 허브")
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let content = NSVisualEffectView(frame: panel.contentView!.bounds)
        content.material = .popover
        content.state = .active
        content.blendingMode = .behindWindow
        content.wantsLayer = true
        content.layer?.cornerRadius = 14
        content.layer?.masksToBounds = true
        panel.contentView = content
        self.panel = panel

        paw.frame = NSRect(x: 390, y: 326, width: 120, height: 160)
        paw.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        content.addSubview(paw)
        tabs.orientation = .horizontal
        tabs.spacing = 6
        tabs.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        let tabsScroll = NSScrollView(frame: NSRect(x: 16, y: 296, width: 820, height: 32))
        tabsScroll.autoresizingMask = [.width, .minYMargin]
        tabsScroll.drawsBackground = false
        tabsScroll.hasHorizontalScroller = true
        tabsScroll.autohidesScrollers = true
        tabs.frame = NSRect(x: 0, y: 0, width: 820, height: 30)
        tabsScroll.documentView = tabs
        content.addSubview(tabsScroll)
        let add = button("plus", "작업 폴더 추가", #selector(addWorkspace))
        add.frame = NSRect(x: 850, y: 298, width: 30, height: 28)
        add.autoresizingMask = [.minXMargin, .minYMargin]
        content.addSubview(add)

        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        collection.collectionViewLayout = layout
        collection.backgroundColors = [.clear]
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.dataSource = self
        collection.delegate = self
        collection.register(FolderFileItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("file"))
        let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        collection.registerForDraggedTypes([.fileURL, .png, .tiff] + promiseTypes)
        collection.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        collection.setDraggingSourceOperationMask(.copy, forLocal: true)
        collection.onKey = { [weak self] in self?.keyDown($0) ?? false }
        collection.makeMenu = { [weak self] in self?.fileMenu() ?? NSMenu() }
        collection.openItem = { [weak self] index, flags in self?.openFile(index, flags: flags) }
        let scroll = NSScrollView(frame: NSRect(x: 10, y: 48, width: 880, height: 242))
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        collection.frame = NSRect(origin: .zero, size: scroll.contentSize)
        collection.autoresizingMask = [.width]
        scroll.documentView = collection
        content.addSubview(scroll)

        let up = button("chevron.up", "상위 폴더", #selector(goUp))
        up.frame = NSRect(x: 14, y: 14, width: 26, height: 26)
        content.addSubview(up)
        path.frame = NSRect(x: 46, y: 15, width: 550, height: 24)
        path.autoresizingMask = [.width]
        path.pathStyle = .standard
        path.target = self
        path.doubleAction = #selector(jumpPath)
        content.addSubview(path)
        status.font = .systemFont(ofSize: 10)
        status.textColor = .secondaryLabelColor
        status.frame = NSRect(x: 18, y: 335, width: 350, height: 36)
        status.lineBreakMode = .byTruncatingTail
        status.maximumNumberOfLines = 2
        status.autoresizingMask = [.minYMargin]
        content.addSubview(status)
        let controls = [("arrow.clockwise", "새로고침", #selector(refresh)), ("square.grid.2x2", "격자 / 목록 보기", #selector(toggleView)), ("pin", "창 고정", #selector(togglePin)), ("ellipsis.circle", "폴더 작업", #selector(showMenu)), ("xmark", "폴더 허브 닫기", #selector(closePanel))]
        for (i, entry) in controls.enumerated() {
            let control = button(entry.0, entry.1, entry.2)
            control.frame = NSRect(x: 716 + CGFloat(i) * 34, y: 14, width: 28, height: 26)
            control.autoresizingMask = [.minXMargin]
            content.addSubview(control)
            if i == 1 { viewButton = control }
            if i == 2 { pinButton = control }
        }
        updateButtons()
        rebuildTabs()
    }

    private func button(_ symbol: String, _ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!, target: self, action: action)
        button.bezelStyle = .inline
        button.isBordered = false
        button.toolTip = title
        button.setAccessibilityLabel(title)
        return button
    }

    private func rebuildTabs() {
        for view in tabs.arrangedSubviews { tabs.removeArrangedSubview(view); view.removeFromSuperview() }
        for workspace in workspaces {
            let button = FolderWorkspaceButton(title: workspace.title, target: self, action: #selector(workspaceClicked(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(workspace.id.uuidString)
            button.bezelStyle = .rounded
            button.setButtonType(.toggle)
            button.state = workspace.id == selectedWorkspace ? .on : .off
            button.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.onHover = { [weak self] in
                guard let self, !self.dragging, !self.busy, self.selectedWorkspace != workspace.id else { return }
                self.selectWorkspace(workspace.id)
            }
            tabs.addArrangedSubview(button)
        }
        tabs.layoutSubtreeIfNeeded()
        tabs.setFrameSize(NSSize(width: max(1, tabs.fittingSize.width), height: 30))
    }

    @objc private func workspaceClicked(_ sender: NSButton) {
        selectWorkspace(sender.identifier.flatMap { UUID(uuidString: $0.rawValue) })
    }

    private func selectWorkspace(_ id: UUID?) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        do {
            var stale = false
            let root = try URL(resolvingBookmarkData: workspace.bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            selectedWorkspace = workspace.id
            UserDefaults.standard.set(workspace.id.uuidString, forKey: "folderHubSelected")
            if stale, let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
                workspaces[index].bookmark = try root.bookmarkData()
                saveWorkspaces()
            }
            rebuildTabs()
            navigate(locations[workspace.id] ?? root)
        } catch {
            directory = nil; files = []; path.url = nil
            watcher?.cancel(); watcher = nil; loadID = UUID()
            collection.reloadData()
            status.stringValue = "‘\(workspace.title)’ 폴더를 찾을 수 없습니다. 작업 폴더를 다시 추가해 주세요."
        }
    }

    private func saveWorkspaces() {
        if let data = try? JSONEncoder().encode(workspaces) { UserDefaults.standard.set(data, forKey: "folderHubWorkspaces") }
    }

    @objc private func addWorkspace() {
        chooseFolder(prompt: "작업 폴더 추가") { [weak self] urls in
            guard let self else { return }
            do {
                for url in urls {
                    var stale = false
                    let exists = self.workspaces.contains { (try? URL(resolvingBookmarkData: $0.bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)) == url }
                    if !exists { self.workspaces.append(FolderWorkspace(title: url.lastPathComponent, bookmark: try url.bookmarkData())) }
                }
                self.saveWorkspaces()
                self.rebuildTabs()
                self.selectWorkspace(self.workspaces.last?.id)
            } catch { self.report(error) }
        }
    }

    private func chooseFolder(prompt: String, completion: @escaping ([URL]) -> Void) {
        guard let panel else { return }
        let chooser = NSOpenPanel()
        chooser.canChooseFiles = false
        chooser.canChooseDirectories = true
        chooser.allowsMultipleSelection = prompt == "작업 폴더 추가"
        chooser.prompt = prompt
        interacting = true
        chooser.beginSheetModal(for: panel) { [weak self] result in
            self?.interacting = false
            if result == .OK { completion(chooser.urls) }
        }
    }

    private func navigate(_ url: URL) {
        directory = url
        if let selectedWorkspace { locations[selectedWorkspace] = url }
        path.url = url
        refresh()
    }

    @objc private func goUp() { if let directory { navigate(directory.deletingLastPathComponent()) } }
    @objc private func jumpPath() { if let url = path.clickedPathItem?.url { navigate(url) } }

    @objc private func refresh() {
        guard let directory, panel?.isVisible == true else { return }
        let id = UUID(); loadID = id
        let sorting = sort
        status.stringValue = "폴더를 읽는 중…"
        fileQueue.async { [weak self] in
            let result = Result { try FolderFiles.list(directory, sort: sorting) }
            DispatchQueue.main.async {
                guard let self, self.loadID == id else { return }
                switch result {
                case .success(let files):
                    self.files = files
                    self.collection.selectionIndexPaths = []
                    self.collection.reloadData()
                    self.status.stringValue = files.isEmpty ? "빈 폴더입니다. 파일을 이곳으로 끌어오세요." : "\(files.count)개 항목 · Space 미리보기 · \(self.shortcutHint)"
                    self.watch(directory)
                case .failure(let error):
                    self.files = []
                    self.collection.reloadData()
                    self.status.stringValue = error.localizedDescription
                }
            }
        }
    }

    private func watch(_ url: URL) {
        watcher?.cancel(); watcher = nil
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in if self?.busy != true { self?.refresh() } }
        source.setCancelHandler { Darwin.close(descriptor) }
        watcher = source
        source.resume()
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { files.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("file"), for: indexPath) as! FolderFileItem
        let file = files[indexPath.item]
        item.configure(name: file.name, icon: NSWorkspace.shared.icon(forFile: file.url.path), list: listMode, width: itemSize.width)
        if !file.isFolder { item.loadThumbnail(file.url) }
        return item
    }
    private var itemSize: NSSize { listMode ? NSSize(width: max(100, collection.bounds.width - 20), height: 32) : NSSize(width: 88, height: 84) }
    func collectionView(_ collectionView: NSCollectionView, layout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize { itemSize }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        if previewPanel?.isVisible == true { updatePreview() }
    }
    private var selectedFiles: [URL] { collection.selectionIndexPaths.sorted().compactMap { files.indices.contains($0.item) ? files[$0.item].url : nil } }

    private func openFile(_ index: Int, flags: NSEvent.ModifierFlags = []) {
        guard files.indices.contains(index) else { return }
        let file = files[index]
        if flags.contains(.command) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
        else if flags.contains(.control) { airDrop([file.url]) }
        else if file.isFolder { navigate(file.url) }
        else { NSWorkspace.shared.open(file.url) }
    }

    @objc private func toggleView() {
        listMode.toggle()
        UserDefaults.standard.set(listMode, forKey: "folderHubList")
        collection.collectionViewLayout?.invalidateLayout()
        collection.reloadData()
        updateButtons()
    }
    @objc private func togglePin() {
        pinned.toggle()
        UserDefaults.standard.set(pinned, forKey: "folderHubPinned")
        updateButtons()
    }
    private func updateButtons() {
        pinButton?.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: "창 고정")
        pinButton?.setAccessibilityValue(pinned ? "켜짐" : "꺼짐")
        viewButton?.image = NSImage(systemSymbolName: listMode ? "list.bullet" : "square.grid.2x2", accessibilityDescription: "격자 / 목록 보기")
    }
    @objc private func closePanel() { hide() }

    private func keyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": copyFiles(); return true
            case "v": pasteFiles(move: flags.contains(.option)); return true
            default: break
            }
            if event.keyCode == UInt16(kVK_UpArrow) { goUp(); return true }
            if event.keyCode == UInt16(kVK_Delete) { trashFiles(); return true }
        }
        if event.keyCode == UInt16(kVK_Space) { preview(); return true }
        if event.keyCode == UInt16(kVK_Escape) { hide(); return true }
        if event.keyCode == UInt16(kVK_Return), let index = collection.selectionIndexPaths.first { openFile(index.item); return true }
        return false
    }

    @objc private func showMenu(_ sender: NSButton) {
        fileMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY), in: sender)
    }

    private func fileMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        func add(_ title: String, _ action: Selector, enabled: Bool = true) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self; item.isEnabled = enabled && !busy
            return item
        }
        let selected = !selectedFiles.isEmpty
        _ = add("열기", #selector(openSelection), enabled: selected)
        let openWith = add("다음으로 열기", #selector(openSelection), enabled: selectedFiles.count == 1)
        if let url = selectedFiles.first {
            let apps = NSMenu()
            for app in NSWorkspace.shared.urlsForApplications(toOpen: url) {
                let item = apps.addItem(withTitle: app.deletingPathExtension().lastPathComponent, action: #selector(openWithApp(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = app
            }
            openWith.submenu = apps
        }
        _ = add("미리보기", #selector(preview), enabled: selected)
        _ = add("Finder에서 보기", #selector(reveal), enabled: directory != nil)
        _ = add("공유…", #selector(share), enabled: selected)
        _ = add("AirDrop…", #selector(airDropSelection), enabled: selected)
        menu.addItem(.separator())
        _ = add("복사", #selector(copyFiles), enabled: selected)
        _ = add("붙여넣기", #selector(pasteCopy), enabled: directory != nil)
        _ = add("여기로 이동 (⌘⌥V)", #selector(pasteMove), enabled: directory != nil)
        _ = add("선택 항목 이동…", #selector(moveSelection), enabled: selected)
        _ = add("이름 변경…", #selector(renameFile), enabled: selectedFiles.count == 1)
        _ = add("휴지통으로 이동", #selector(trashFiles), enabled: selected)
        _ = add("새 폴더…", #selector(newFolder), enabled: directory != nil)
        menu.addItem(.separator())
        let sortMenu = NSMenu()
        for sorting in FolderSort.allCases {
            let item = sortMenu.addItem(withTitle: sorting.title, action: #selector(changeSort(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = sorting.rawValue
            item.state = sort == sorting ? .on : .off
        }
        add("정렬", #selector(refresh)).submenu = sortMenu
        _ = add("작업 폴더 추가…", #selector(addWorkspace))
        _ = add("현재 작업 폴더 이름 변경…", #selector(renameWorkspace), enabled: selectedWorkspace != nil)
        _ = add("현재 작업 폴더 등록 해제", #selector(removeWorkspace), enabled: selectedWorkspace != nil)
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) { interacting = true; hideTask?.cancel(); hideTask = nil }
    func menuDidClose(_ menu: NSMenu) { interacting = false }
    @objc private func openSelection() { for index in collection.selectionIndexPaths.sorted() { openFile(index.item) } }
    @objc private func openWithApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(selectedFiles, withApplicationAt: app, configuration: .init()) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.report(error) } }
        }
    }
    @objc private func reveal() {
        let urls = selectedFiles.isEmpty ? directory.map { [$0] } ?? [] : selectedFiles
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
    @objc private func copyFiles() {
        guard !selectedFiles.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(selectedFiles as [NSURL])
    }
    @objc private func pasteCopy() { pasteFiles(move: false) }
    @objc private func pasteMove() { pasteFiles(move: true) }
    private func pasteFiles(move: Bool) {
        guard let directory, let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return }
        perform { try FolderFiles.transfer(urls, to: directory, move: move) }
    }
    @objc private func moveSelection() {
        let urls = selectedFiles
        chooseFolder(prompt: "이동할 폴더 선택") { [weak self] targets in
            guard let target = targets.first else { return }
            self?.perform { try FolderFiles.transfer(urls, to: target, move: true) }
        }
    }
    @objc private func trashFiles() {
        let urls = selectedFiles
        guard !urls.isEmpty, let panel else { return }
        let alert = NSAlert()
        alert.messageText = "선택한 \(urls.count)개 항목을 휴지통으로 이동할까요?"
        alert.informativeText = "Finder의 휴지통에서 복원할 수 있습니다."
        alert.addButton(withTitle: "휴지통으로 이동"); alert.addButton(withTitle: "취소")
        alert.beginSheetModal(for: panel) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.perform { for url in urls { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } } }
        }
    }
    private func promptName(_ title: String, value: String = "", completion: @escaping (String) -> Void) {
        guard let panel else { return }
        let alert = NSAlert()
        alert.messageText = title
        let input = NSTextField(string: value)
        input.frame = NSRect(x: 0, y: 0, width: 300, height: 26)
        alert.accessoryView = input
        alert.addButton(withTitle: "확인"); alert.addButton(withTitle: "취소")
        alert.window.initialFirstResponder = input
        alert.beginSheetModal(for: panel) { response in if response == .alertFirstButtonReturn { completion(input.stringValue) } }
    }
    @objc private func renameFile() {
        guard let source = selectedFiles.first else { return }
        promptName("이름 변경", value: source.lastPathComponent) { [weak self] name in
            guard name != source.lastPathComponent else { return }
            self?.perform { try FileManager.default.moveItem(at: source, to: FolderFiles.namedURL(name, in: source.deletingLastPathComponent())) }
        }
    }
    @objc private func newFolder() {
        guard let directory else { return }
        promptName("새 폴더 이름") { [weak self] name in
            self?.perform { try FileManager.default.createDirectory(at: FolderFiles.namedURL(name, in: directory), withIntermediateDirectories: false) }
        }
    }
    @objc private func renameWorkspace() {
        guard let index = workspaces.firstIndex(where: { $0.id == selectedWorkspace }) else { return }
        promptName("작업 폴더 표시 이름", value: workspaces[index].title) { [weak self] name in
            guard let self, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            self.workspaces[index].title = name
            self.saveWorkspaces(); self.rebuildTabs()
        }
    }
    @objc private func removeWorkspace() {
        workspaces.removeAll { $0.id == selectedWorkspace }
        if let selectedWorkspace { locations.removeValue(forKey: selectedWorkspace) }
        selectedWorkspace = nil; directory = nil; path.url = nil
        files = []; collection.reloadData()
        watcher?.cancel(); watcher = nil; loadID = UUID()
        saveWorkspaces(); rebuildTabs()
        status.stringValue = "작업 폴더를 추가해 주세요. 원본 파일은 삭제하지 않습니다."
        selectWorkspace(workspaces.first?.id)
    }
    @objc private func changeSort(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let sort = FolderSort(rawValue: raw) else { return }
        self.sort = sort
        UserDefaults.standard.set(raw, forKey: "folderHubSort")
        refresh()
    }

    private func perform(_ operation: @escaping () throws -> Void) {
        guard !busy else { return }
        busy = true; status.stringValue = "파일 작업 중…"
        fileQueue.async { [weak self] in
            let result = Result { try operation() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.refresh()
                if case .failure(let error) = result { self.report(error) }
            }
        }
    }
    private func report(_ error: Error) {
        guard let panel else { return }
        let alert = NSAlert(error: error)
        alert.beginSheetModal(for: panel)
    }

    @objc private func preview() {
        guard !selectedFiles.isEmpty else { return }
        if previewPanel?.isVisible == true { previewPanel?.orderOut(nil); return }
        if previewPanel == nil {
            let preview = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 480), styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            preview.isReleasedWhenClosed = false
            preview.level = .popUpMenu
            preview.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = QLPreviewView(frame: preview.contentView!.bounds, style: .normal)!
            view.autoresizingMask = [.width, .height]
            preview.contentView?.addSubview(view)
            previewPanel = preview; previewView = view
        }
        updatePreview()
        previewPanel?.center()
        previewPanel?.makeKeyAndOrderFront(nil)
    }
    private func updatePreview() {
        guard let url = selectedFiles.first else { return }
        previewPanel?.title = url.lastPathComponent
        previewView?.previewItem = url as NSURL
    }
    @objc private func share() {
        guard !selectedFiles.isEmpty else { return }
        sharingPicker = NSSharingServicePicker(items: selectedFiles)
        sharingPicker?.delegate = self
        interacting = true
        sharingPicker?.show(relativeTo: collection.visibleRect, of: collection, preferredEdge: .minY)
    }
    @objc private func airDropSelection() { airDrop(selectedFiles) }
    private func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        sharingService = NSSharingService(named: .sendViaAirDrop)
        sharingService?.delegate = self
        interacting = sharingService != nil
        sharingService?.perform(withItems: urls)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        sharingService = service
        service?.delegate = self
        interacting = service != nil
    }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { interacting = false }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) { interacting = false }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? { files[indexPath.item].url as NSURL }
    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        dragging = true
        hideTask?.cancel(); hideTask = nil
    }
    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) { dragging = false; refresh(); pointerMoved() }
    func collectionView(_ collectionView: NSCollectionView, validateDrop info: NSDraggingInfo, proposedIndexPath proposed: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation operation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        guard directory != nil, !busy else { return [] }
        let point = collectionView.convert(info.draggingLocation, from: nil)
        if let index = collectionView.indexPathForItem(at: point), files.indices.contains(index.item), files[index.item].isFolder {
            proposed.pointee = index as NSIndexPath
            operation.pointee = .on
        } else { operation.pointee = .before }
        return .copy
    }
    func collectionView(_ collectionView: NSCollectionView, acceptDrop info: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        guard let directory, !busy else { return false }
        let target = dropOperation == .on && files.indices.contains(indexPath.item) && files[indexPath.item].isFolder ? files[indexPath.item].url : directory
        let pasteboard = info.draggingPasteboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            perform { try FolderFiles.transfer(urls, to: target, move: false) }
            return true
        }
        if let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver], !receivers.isEmpty {
            receivePromises(receivers, target: target)
            return true
        }
        if let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            perform { try png.write(to: target.appendingPathComponent("이미지-\(UUID().uuidString).png"), options: .withoutOverwriting) }
            return true
        }
        return false
    }

    private func receivePromises(_ receivers: [NSFilePromiseReceiver], target: URL) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        for receiver in receivers {
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do { try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false) }
            catch { report(error); continue }
            var remaining = receiver.fileNames.count
            receiver.receivePromisedFiles(atDestination: staging, options: [:], operationQueue: queue) { [weak self] url, error in
                defer {
                    remaining -= 1
                    if remaining <= 0 { try? FileManager.default.removeItem(at: staging) }
                }
                do {
                    if let error { throw error }
                    try FolderFiles.transfer([url], to: target, move: true)
                    DispatchQueue.main.async { self?.refresh() }
                } catch { DispatchQueue.main.async { self?.report(error) } }
            }
        }
    }
}
