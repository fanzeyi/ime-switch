import AppKit

/// Finds the caret the way the system switcher does, from the app's own
/// `NSTextInputClient.firstRect`. That works where the Accessibility API has no caret
/// (Ghostty) or reports a wrong one (TextEdit, System Settings).
///
/// The system input source switcher draws its strip inside the frontmost app, which
/// places it at its own caret. HIToolbox in every app listens on a per-process
/// CFMessagePort, "com.apple.tsm.portname", for the switcher's show and hide messages.
/// So we ask the app to show the strip, read where its window lands, and hide it again
/// right away. The strip briefly shows on screen; that can't be avoided, since the app
/// only places the window as it shows it. It lists just one source to stay small (an
/// empty list leaves the app's switcher unable to show again). None of this is public API; if any of it stops working, the probe just
/// finds nothing and the HUD falls back to `CaretLocator`.
@MainActor
enum SwitcherCaretProbe {
    private static let portName = "com.apple.tsm.portname" as CFString
    // Message IDs and keys handled by HIToolbox's TSMMessagePortCallBack.
    private static let showMessage: Int32 = 9
    private static let hideMessage: Int32 = 10
    private static let sourceIDsKey = "tsmEnabledInputSourceIDs"
    private static let selectionKey = "tsmSelection"

    /// The strip window is 83pt tall whatever the number of sources, and its top sits
    /// 26pt above the caret's bottom, with the caret at its horizontal center.
    private static let stripHeight: CGFloat = 83
    private static let stripTopToCaretBottom: CGFloat = 26

    /// How long to wait for the strip to appear before giving up, e.g. when no text field
    /// is focused. It usually shows up within 40–80 ms.
    private static let timeout: TimeInterval = 0.15
    private static let pollInterval: TimeInterval = 0.005

    private typealias CreatePerProcessRemote = @convention(c) (CFAllocator?, CFString, CFIndex) -> Unmanaged<CFMessagePort>?
    private static let createPerProcessRemote: CreatePerProcessRemote? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "CFMessagePortCreatePerProcessRemote") else { return nil }
        return unsafeBitCast(symbol, to: CreatePerProcessRemote.self)
    }()

    /// Calls `completion` with the frontmost app's caret (a zero-size rect at the caret's
    /// bottom, in Cocoa screen coordinates), or nil if the app shows no strip, e.g. because
    /// no text field is focused. `sourceID` is the one source the probe strip lists.
    static func locate(sourceID: String, completion: @escaping @MainActor (NSRect?) -> Void) {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let port = createPerProcessRemote?(nil, portName, CFIndex(pid))?.takeRetainedValue()
        else {
            completion(nil)
            return
        }
        let alreadyShown = Set(stripWindows(of: pid).map(\.number))
        guard send(port, showMessage, [sourceIDsKey: [sourceID], selectionKey: 0]) else {
            completion(nil)
            return
        }

        Task { @MainActor in
            let deadline = Date().addingTimeInterval(timeout)
            var strip = stripWindows(of: pid).first { !alreadyShown.contains($0.number) }
            while strip == nil, Date() < deadline {
                try? await Task.sleep(for: .seconds(pollInterval))
                strip = stripWindows(of: pid).first { !alreadyShown.contains($0.number) }
            }
            send(port, hideMessage, [:])
            let caret = strip.map { caret(below: $0.bounds) }
            caretLog.debug("probe pid \(pid): strip \(strip.map { NSStringFromRect($0.bounds) } ?? "none", privacy: .public) → caret \(caret?.debugDescription ?? "nil", privacy: .public)")
            completion(caret)
        }
    }

    @discardableResult
    private static func send(_ port: CFMessagePort, _ message: Int32, _ info: [String: Any]) -> Bool {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0) else {
            return false
        }
        return CFMessagePortSendRequest(port, message, data as CFData, 0.05, 0, nil, nil) == kCFMessagePortSuccess
    }

    /// On-screen windows of `pid` shaped like the switcher strip, in CG coordinates.
    private static func stripWindows(of pid: pid_t) -> [(number: Int, bounds: CGRect)] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  let number = window[kCGWindowNumber as String] as? Int,
                  let boundsInfo = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.height == stripHeight
            else { return nil }
            return (number, bounds)
        }
    }

    private static func caret(below strip: CGRect) -> NSRect {
        // CG window bounds use a top-left origin on the primary screen.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: strip.midX, y: primaryHeight - (strip.minY + stripTopToCaretBottom), width: 0, height: 0)
    }
}
