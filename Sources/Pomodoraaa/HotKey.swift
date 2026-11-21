import Carbon.HIToolbox
import Foundation

/// System-wide keyboard shortcuts (work from any app, no Accessibility permission needed).
@MainActor
final class HotKey {
    static var handlers: [UInt32: @MainActor () -> Void] = [:]
    private static var handlerInstalled = false

    private var ref: EventHotKeyRef?

    init(id: UInt32, keyCode: Int, modifiers: Int, handler: @escaping @MainActor () -> Void) {
        HotKey.handlers[id] = handler
        HotKey.installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x504F_4D4F), id: id) // 'POMO'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                            GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, nil)
        handlerInstalled = true
    }
}

private func hotKeyEventHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr else { return status }
    let id = hotKeyID.id
    Task { @MainActor in HotKey.handlers[id]?() }
    return noErr
}
