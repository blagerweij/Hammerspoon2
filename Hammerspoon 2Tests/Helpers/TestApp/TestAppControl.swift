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
/// Two ways to use it. A suite that only needs the app to be there takes the `.testApp` trait:
/// one copy runs for the whole suite, and `pid` names it (in JS: `hs.application.fromPID(pid)`).
/// A test about launching or quitting calls `launch(detail:)` itself and quits what it launched.
/// Every copy is addressed by its pid, so suites running side by side don't disturb each other.
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

    /// The copy the `.testApp` trait launched for the running suite; nil outside such a suite.
    @TaskLocal static var pid: pid_t?

    /// Launches a new copy in the background and waits until its window is on screen. Only then
    /// is it ready: `hide()` right after `isFinishedLaunching` does nothing.
    /// - Parameter detail: What the test checks; shown in the app's window below the test's name
    /// - Returns: The running app, or nil when it couldn't be launched or showed no window in
    ///   time; both are recorded as an issue, so a caller that returns early still fails
    @MainActor
    static func launch(detail: String = "") async -> NSRunningApplication? {
        guard let url else { return nil }
        _ = leftoversQuit
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["-test", currentTestName, "-detail", detail]
        let app: NSRunningApplication
        do {
            app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            Issue.record("The test app could not be launched: \(error.localizedDescription)")
            return nil
        }
        let deadline = Date().addingTimeInterval(5)
        while !isReady(app), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard isReady(app) else {
            Issue.record("The test app showed no window within 5 s")
            app.terminate()
            return nil
        }
        return app
    }

    /// `launch(detail:)` for callers off the main actor, which can't take the app object across.
    @MainActor
    static func launchedPID(detail: String) async -> pid_t? {
        await launch(detail: detail)?.processIdentifier
    }

    /// Copies an earlier, aborted test run left behind are quit before the first launch of this run.
    @MainActor
    private static let leftoversQuit: Void = {
        NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }.forEach { $0.terminate() }
    }()

    private static var currentTestName: String { Test.current?.displayName ?? Test.current?.name ?? "" }

    private static func isReady(_ app: NSRunningApplication) -> Bool {
        app.isFinishedLaunching && hasWindowOnScreen(app)
    }

    private static func hasWindowOnScreen(_ app: NSRunningApplication) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier }
    }

    // MARK: - Commands to a running copy

    /// Shows the running test's name in the suite's copy, and what it checks.
    static func showCurrentTest(detail: String = "") {
        send("show", to: pid, ["test": currentTestName, "detail": detail])
    }

    /// Has a copy open one more window.
    /// - Parameter pid: The copy; the suite's copy by default
    static func openWindow(in pid: pid_t? = TestAppControl.pid) {
        send("newWindow", to: pid)
    }

    /// Has a copy close the windows `openWindow` opened.
    /// - Parameter pid: The copy; the suite's copy by default
    static func closeWindows(in pid: pid_t? = TestAppControl.pid) {
        send("closeWindows", to: pid)
    }

    private static func send(_ command: String, to pid: pid_t?, _ arguments: [String: String] = [:]) {
        guard let pid else { return }
        var userInfo = arguments
        userInfo["command"] = command
        userInfo["pid"] = String(pid)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("\(bundleID).command"), object: nil, userInfo: userInfo, deliverImmediately: true)
    }
}

/// Runs one copy of the test app for the whole suite; `TestAppControl.pid` names it.
nonisolated struct TestAppTrait: SuiteTrait, TestScoping {
    @concurrent
    func provideScope(for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void) async throws {
        // launch(detail:) has recorded why when there is no pid
        guard let pid = await TestAppControl.launchedPID(detail: "One copy for the whole suite") else { return }
        defer { NSRunningApplication(processIdentifier: pid)?.terminate() }
        try await TestAppControl.$pid.withValue(pid) { try await function() }
    }
}

nonisolated extension Trait where Self == TestAppTrait {
    /// Runs one copy of the Hammerspoon 2 Test App for the whole suite.
    static var testApp: Self { Self() }
}
