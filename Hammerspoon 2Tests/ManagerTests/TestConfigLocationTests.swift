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
    @Test("The host app's config is the one in Hammerspoon 2Tests/Fixtures/Config")
    func testHostRunsTestConfig() {
        // Set by the Development scheme's Test action: -configLocation "$(SRCROOT)/Hammerspoon 2Tests/Fixtures/Config/init.js"
        let expected = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Config/init.js")
        #expect(SettingsManager.shared.configLocation.standardizedFileURL.path == expected.standardizedFileURL.path)
    }
}
