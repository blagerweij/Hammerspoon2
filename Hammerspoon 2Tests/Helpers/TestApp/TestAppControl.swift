//
//  TestAppControl.swift
//  Hammerspoon 2Tests
//

import AppKit
import Testing

/// Builds, launches and drives the "Hammerspoon 2 Test App" from the tests (the app itself is a
/// separate program). It is the app tests launch, hide, quit and open windows in when they need
/// a real other application, instead of Finder or Chess. It starts in about 0.2 s, shows nothing
/// personal, and its window says which test is running.
///
/// Its source is `TestApp.swift` next to this file; `build-test-app.sh`, also here, builds it on
/// first use and after a change.
nonisolated enum TestAppControl {
    static let bundleID = "net.tenshu.Hammerspoon-2.TestApp"

    /// The built app, or nil when it couldn't be built. Built once per test run.
    static let url: URL? = {
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("build-test-app.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        let output = Pipe()
        process.standardOutput = output
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }()

    /// For `.enabled(if:)`: whether the app could be built.
    static var isAvailable: Bool { url != nil }

    static var running: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
    }

    /// Launches the app in the background and waits until its window is on screen. Only then is it
    /// ready: `hide()` right after `isFinishedLaunching` does nothing.
    /// - Parameter detail: What the test checks; shown in the app's window below the test's name
    /// - Returns: The running app, or nil when it couldn't be launched
    @MainActor
    static func launch(detail: String = "") async -> NSRunningApplication? {
        guard let url else { return nil }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["-test", Test.current?.displayName ?? Test.current?.name ?? "", "-detail", detail]
        guard let app = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration) else { return nil }
        let deadline = Date().addingTimeInterval(5)
        while !(app.isFinishedLaunching && hasWindowOnScreen(app)), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return app
    }

    private static func hasWindowOnScreen(_ app: NSRunningApplication) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier }
    }

    /// Quits every running copy and waits until they are gone.
    @MainActor
    static func terminateAll() async {
        running.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(5)
        while !running.isEmpty, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Has the running app open one more window.
    static func openWindow() {
        send(["command": "newWindow"])
    }

    private static func send(_ command: [String: String]) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("\(bundleID).command"), object: nil, userInfo: command, deliverImmediately: true)
    }
}
