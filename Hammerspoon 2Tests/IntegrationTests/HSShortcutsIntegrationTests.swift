//
//  HSShortcutsIntegrationTests.swift
//  Hammerspoon 2Tests
//

import Testing
import JavaScriptCore
@testable import Hammerspoon_2

@Suite("hs.shortcuts tests", .serialized)
struct HSShortcutsIntegrationTests {

    // MARK: - API Structure Tests

    @Suite("hs.shortcuts API structure tests")
    struct HSShortcutsStructureTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSShortcutsModule.self, as: "shortcuts")
            return harness
        }

        @Test("hs.shortcuts is an object")
        func testModuleIsObject() {
            #expect(makeHarness().evalTypeOf("hs.shortcuts") == "object")
        }

        @Test("list is a function")
        func testListIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.shortcuts.list") == "function")
        }

        @Test("run is a function")
        func testRunIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.shortcuts.run") == "function")
        }

        @Test("open is a function")
        func testOpenIsFunction() {
            #expect(makeHarness().evalTypeOf("hs.shortcuts.open") == "function")
        }
    }

    // MARK: - Behaviour Tests

    @Suite("hs.shortcuts behaviour tests")
    struct HSShortcutsBehaviourTests {

        private func makeHarness() -> JSTestHarness {
            let harness = JSTestHarness()
            harness.loadModule(HSShortcutsModule.self, as: "shortcuts")
            return harness
        }

        /// The shortcuts the `shortcuts` command-line tool lists, as "name (id)" lines: what
        /// `list()` should return, read without Apple Events.
        private static func shortcutsFromCLI() throws -> [String] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list", "--show-identifiers"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: output, as: UTF8.self).split(separator: "\n").map(String.init)
        }

        /// Puts `list()`'s result in the JS variable `shortcuts`. Fails when it threw or is empty:
        /// the entry checks are vacuous for an empty array, so they'd pass whatever `list()` did.
        private func listShortcuts(into harness: JSTestHarness) throws {
            harness.eval("var shortcuts = hs.shortcuts.list()")
            try #require(!harness.hasException, "list() threw: \(harness.exceptionMessage ?? "")")
            let count = harness.evalValue("shortcuts.length")?.toInt32() ?? 0
            try #require(count > 0, "No shortcuts to check list()'s entries against; create one in the Shortcuts app (the VM's provisioning creates one)")
        }

        @Test("list() returns an array")
        func testListReturnsArray() {
            let harness = makeHarness()
            harness.expectTrue("Array.isArray(hs.shortcuts.list())")
            #expect(!harness.hasException)
        }

        @Test("list() returns the shortcuts the shortcuts command-line tool lists")
        func testListMatchesCLI() throws {
            let expected = try Self.shortcutsFromCLI()
            try #require(!expected.isEmpty, "No shortcuts to compare list() with; create one in the Shortcuts app (the VM's provisioning creates one)")
            let harness = makeHarness()
            let listed = harness.evalValue("hs.shortcuts.list().map(s => s.name + ' (' + s.id + ')')")?.toArray() as? [String]
            #expect(!harness.hasException, "list() threw: \(harness.exceptionMessage ?? "")")
            #expect(listed?.sorted() == expected.sorted())
        }

        @Test("list() entries each have a name string")
        func testListEntriesHaveName() throws {
            let harness = makeHarness()
            try listShortcuts(into: harness)
            harness.expectTrue("shortcuts.every(s => typeof s.name === 'string')")
        }

        @Test("list() entries each have an id string")
        func testListEntriesHaveId() throws {
            let harness = makeHarness()
            try listShortcuts(into: harness)
            harness.expectTrue("shortcuts.every(s => typeof s.id === 'string')")
        }

        @Test("list() entries each have an acceptsInput boolean")
        func testListEntriesHaveAcceptsInput() throws {
            let harness = makeHarness()
            try listShortcuts(into: harness)
            harness.expectTrue("shortcuts.every(s => typeof s.acceptsInput === 'boolean')")
        }

        @Test("list() entries each have an actionCount number")
        func testListEntriesHaveActionCount() throws {
            let harness = makeHarness()
            try listShortcuts(into: harness)
            harness.expectTrue("shortcuts.every(s => typeof s.actionCount === 'number')")
        }

        @Test("list() throws when Shortcuts Events can't be asked")
        func testListThrowsOnFailure() throws {
            let harness = makeHarness()
            let module = try #require(harness.evalValue("hs.shortcuts")?.toObjectOf(HSShortcutsModule.self) as? HSShortcutsModule)
            module.shortcutsEventsBundleID = "net.tenshu.Hammerspoon-2.NoSuchApp"

            harness.eval("hs.shortcuts.list()")

            #expect(harness.exceptionMessage?.contains("hs.shortcuts.list():") == true, "got: \(harness.exceptionMessage ?? "no exception")")
        }

        @Test("run() returns a Promise")
        func testRunReturnsPromise() {
            let harness = makeHarness()
            harness.expectTrue("hs.shortcuts.run('__test__') instanceof Promise")
            #expect(!harness.hasException)
        }

        @Test("run() of a non-existent shortcut rejects")
        @MainActor
        func testRunNonExistentShortcutRejects() async {
            let harness = JSTestHarness()
            harness.loadModule(HSShortcutsModule.self, as: "shortcuts")

            var rejected = false
            harness.registerCallback("onRejected") {
                rejected = true
            }
            harness.eval("""
                hs.shortcuts.run('__hammerspoon_nonexistent_shortcut__')
                    .catch(() => __test_callback('onRejected'))
            """)
            #expect(!harness.hasException)

            let ok = await harness.waitForAsync(timeout: 10.0) { rejected }
            #expect(ok, "Promise should reject for a non-existent shortcut")
            #expect(rejected)
        }

        @Test("open() asks the Shortcuts app for the shortcut by name, escaped in the URL")
        func testOpenBuildsShortcutURL() throws {
            let harness = makeHarness()
            let module = try #require(harness.evalValue("hs.shortcuts")?.toObjectOf(HSShortcutsModule.self) as? HSShortcutsModule)
            // Catches the URL instead of opening it: the Shortcuts app would come up, show an error
            // dialog for a name it doesn't know, and stay open after the test run.
            var opened: [String] = []
            module.urlOpener = { opened.append($0.absoluteString) }

            harness.eval("hs.shortcuts.open('Tom & Jerry ü')")

            #expect(!harness.hasException)
            #expect(opened == ["shortcuts://open-shortcut?name=Tom%20%26%20Jerry%20%C3%BC"])
        }
    }
}
