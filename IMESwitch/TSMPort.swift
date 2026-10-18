import AppKit

/// HIToolbox in every app listens on a per-process CFMessagePort, "com.apple.tsm.portname",
/// for messages from the system's text input UI: the input source switcher and the Input
/// menu in the menu bar. None of this is public API; callers fall back when a send fails.
@MainActor
enum TSMPort {
    // Message IDs handled by HIToolbox's TSMMessagePortCallBack.
    /// The Input menu selecting a source, with `selectedSourceKey`.
    static let selectSourceMessage: Int32 = 7
    /// The switcher strip showing, with `switcherSourceIDsKey` and `switcherSelectionKey`.
    static let showSwitcherMessage: Int32 = 9
    static let hideSwitcherMessage: Int32 = 10

    static let selectedSourceKey = "tsmInputSourceSelectedInpSrcKey"
    static let switcherSourceIDsKey = "tsmEnabledInputSourceIDs"
    static let switcherSelectionKey = "tsmSelection"

    private static let portName = "com.apple.tsm.portname" as CFString

    private typealias CreatePerProcessRemote = @convention(c) (CFAllocator?, CFString, CFIndex) -> Unmanaged<CFMessagePort>?
    private static let createPerProcessRemote: CreatePerProcessRemote? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "CFMessagePortCreatePerProcessRemote") else { return nil }
        return unsafeBitCast(symbol, to: CreatePerProcessRemote.self)
    }()

    static func port(of pid: pid_t) -> CFMessagePort? {
        createPerProcessRemote?(nil, portName, CFIndex(pid))?.takeRetainedValue()
    }

    @discardableResult
    static func send(_ port: CFMessagePort, _ message: Int32, _ info: [String: Any]) -> Bool {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0) else {
            return false
        }
        return CFMessagePortSendRequest(port, message, data as CFData, 0.05, 0, nil, nil) == kCFMessagePortSuccess
    }
}
