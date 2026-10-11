import ServiceManagement

/// Opening Hoop at login, as one of the system's Login Items.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Turns opening at login on or off. macOS can hold a new login item until the user approves
    /// it; then this opens Login Items in System Settings.
    static func toggle() throws {
        let app = SMAppService.mainApp
        switch app.status {
        case .enabled:
            try app.unregister()
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        default:
            try app.register()
            if app.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        }
    }
}
