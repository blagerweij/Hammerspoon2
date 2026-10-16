//
//  HSDocsIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
import JavaScriptCore
import AppKit
@testable import Hammerspoon_2

/// See HSUIWebViewTests: only `TEST_RUNNER_`-prefixed vars reach the test host, so CI sets
/// `TEST_RUNNER_CI=true`.
private nonisolated func isRunningInCI() -> Bool {
    ProcessInfo.processInfo.environment["CI"] != nil
}

@Suite("hs.docs tests")
@MainActor
struct HSDocsIntegrationTests {

    private func makeHarness() throws -> (JSTestHarness, HSDocsModule) {
        let harness = JSTestHarness()
        harness.loadModule(HSUIModule.self, as: "ui")
        harness.loadModule(HSDocsModule.self, as: "docs")
        let docs = try #require(harness.evalValue("hs.docs")?.toObject() as? HSDocsModule)
        return (harness, docs)
    }

    @Test(
        "show() while the docs window is open reuses it instead of opening another",
        .disabled(if: isRunningInCI(), "WebKit CVDisplayLink UAF crash in GitHub's virtualized macOS runner — see QUARANTINED IN CI in HSUIWebViewTests")
    )
    func testShowReusesOpenWindow() throws {
        let (harness, docs) = try makeHarness()

        harness.eval("hs.docs.show(); void 0")
        let window = try #require(docs.docsWindow)
        #expect(window.isShown)

        harness.eval("hs.docs.show(); void 0")
        harness.eval("hs.docs.show('hs.application'); void 0")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        #expect(!harness.hasException)
        #expect(docs.docsWindow === window)
        #expect(NSApp.windows.filter { ($0.delegate as AnyObject?) === window && $0.isVisible }.count == 1)
        window.destroy()
    }

    @Test(
        "show() with no module keeps the page the user navigated to, and switches between JS and TS docs",
        .disabled(if: isRunningInCI(), "WebKit CVDisplayLink UAF crash in GitHub's virtualized macOS runner — see QUARANTINED IN CI in HSUIWebViewTests")
    )
    func testShowFollowsWhatTheWebViewIsShowing() async throws {
        let (harness, docs) = try makeHarness()
        let jsPath = try #require(docs.jsDocsPath())
        let tsPath = try #require(docs.tsDocsPath())

        harness.eval("hs.docs.show(); void 0")
        let window = try #require(docs.docsWindow)
        let webView = try #require(docs.docsWebView)
        func currentPath() -> String? { webView.url.flatMap { URL(string: $0) }?.path }

        #expect(await harness.waitForAsync(timeout: 5) { currentPath() == "\(jsPath)/index.html" })

        // Switching to TS docs navigates even with no module given
        harness.eval("hs.docs.show(undefined, true); void 0")
        #expect(await harness.waitForAsync(timeout: 5) { currentPath() == "\(tsPath)/index.html" })

        // The user navigates back to a JS page; a bare show() must leave it there
        _ = webView.loadURL("file://\(jsPath)/hs.application.html")
        #expect(await harness.waitForAsync(timeout: 5) { currentPath() == "\(jsPath)/hs.application.html" })
        // The page's url briefly reads nil as it settles, so watch it for a while rather than
        // sampling it once: it must never move to the index page.
        harness.eval("hs.docs.show(); void 0")
        var seen: [String?] = []
        for _ in 0..<20 {
            seen.append(currentPath())
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!seen.contains("\(jsPath)/index.html"))
        #expect(await harness.waitForAsync(timeout: 5) { currentPath() == "\(jsPath)/hs.application.html" })

        #expect(!harness.hasException)
        window.destroy()
    }

    @Test(
        "show() after the docs window was closed opens a new one",
        .disabled(if: isRunningInCI(), "WebKit CVDisplayLink UAF crash in GitHub's virtualized macOS runner — see QUARANTINED IN CI in HSUIWebViewTests")
    )
    func testShowAfterHideOpensNewWindow() throws {
        let (harness, docs) = try makeHarness()

        harness.eval("hs.docs.show(); void 0")
        let first = try #require(docs.docsWindow)
        first.hide()

        harness.eval("hs.docs.show(); void 0")
        let second = try #require(docs.docsWindow)

        #expect(!harness.hasException)
        #expect(second !== first)
        #expect(second.isShown)
        first.destroy()
        second.destroy()
    }
}
