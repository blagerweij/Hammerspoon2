//
//  TestConfigLocationTests.swift
//  Hammerspoon 2Tests
//

import Foundation
import Testing
@testable import Hammerspoon_2

/// The app that hosts the tests runs the test config, not the developer's own init.js.
@Suite("Test config location")
struct TestConfigLocationTests {
    @Test("The host app's config is the empty one in Hammerspoon 2Tests/Fixtures/Config")
    func testHostRunsTestConfig() throws {
        // Set by the schemes' Test action: -configLocation "$(SRCROOT)/Hammerspoon 2Tests/Fixtures/Config/init.js".
        // hs2vm's guest runner points it at the test bundle's copy, since the guest has no source tree.
        // Compared by contents rather than path, so a config that doesn't exist fails too.
        let fixture = try #require(Bundle(for: JSTestHarness.self).url(forResource: "init", withExtension: "js"))
        let configLocation = SettingsManager.shared.configLocation
        let config = try String(contentsOf: configLocation, encoding: .utf8)
        #expect(config == (try String(contentsOf: fixture, encoding: .utf8)), "the host app runs \(configLocation.path)")
    }
}
