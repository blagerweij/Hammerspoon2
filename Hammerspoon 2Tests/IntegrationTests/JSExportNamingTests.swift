//
//  JSExportNamingTests.swift
//  Hammerspoon 2Tests
//

import Testing
import Foundation
import JavaScriptCore
import ObjectiveC
@testable import Hammerspoon_2

/// Objective-C methods whose selectors are in the alloc/new/copy/mutableCopy families return an
/// object with an extra retain that the caller must release. JavaScriptCore doesn't release it, so
/// every object such a method returns to JS leaks (#309). This checks that no JSExport protocol
/// declares one.
@Suite("JSExport naming tests")
struct JSExportNamingTests {

    private static let retainedFamilies = ["alloc", "new", "copy", "mutableCopy"]

    /// The ObjC method family rules: ignoring leading underscores, the selector starts with the
    /// family name, followed by anything other than a lowercase letter.
    private static func retainedFamily(of selector: String) -> String? {
        let name = selector.drop { $0 == "_" }
        return retainedFamilies.first { family in
            guard name.hasPrefix(family) else { return false }
            guard let next = name.dropFirst(family.count).first else { return true }
            return !next.isLowercase
        }
    }

    /// Whether an ObjC method type encoding returns an object, skipping type qualifiers.
    private static func returnsObject(_ types: UnsafePointer<CChar>?) -> Bool {
        guard let types else { return false }
        let encoding = String(cString: types).drop { "rnNoORV".contains($0) }
        return encoding.first == "@"
    }

    /// Every protocol adopted, directly or by inheritance, by a class in the app binary. System
    /// frameworks have JSExport protocols of their own (SceneKit's declare `-copy`), which aren't ours to check.
    private static func appProtocols() throws -> [Protocol] {
        let image = try #require(class_getImageName(HSImage.self))
        var classCount: UInt32 = 0
        let classNames = try #require(objc_copyClassNamesForImage(image, &classCount))
        defer { free(UnsafeMutableRawPointer(classNames)) }

        var seen = Set<String>()
        var result: [Protocol] = []
        func visit(_ proto: Protocol) {
            guard seen.insert(String(cString: protocol_getName(proto))).inserted else { return }
            result.append(proto)
            var count: UInt32 = 0
            guard let inherited = protocol_copyProtocolList(proto, &count) else { return }
            defer { free(UnsafeMutableRawPointer(inherited)) }
            UnsafeBufferPointer(start: inherited, count: Int(count)).forEach(visit)
        }
        for name in UnsafeBufferPointer(start: classNames, count: Int(classCount)) {
            guard let cls = objc_getClass(name) as? AnyClass else { continue }
            var count: UInt32 = 0
            guard let adopted = class_copyProtocolList(cls, &count) else { continue }
            defer { free(UnsafeMutableRawPointer(adopted)) }
            UnsafeBufferPointer(start: adopted, count: Int(count)).forEach(visit)
        }
        return result
    }

    @Test("Method family detection matches the Objective-C rules")
    func familyDetection() {
        #expect(Self.retainedFamily(of: "copyImage") == "copy")
        #expect(Self.retainedFamily(of: "copy::") == "copy")
        #expect(Self.retainedFamily(of: "newWindow:") == "new")
        #expect(Self.retainedFamily(of: "mutableCopy") == "mutableCopy")
        #expect(Self.retainedFamily(of: "_allocThing") == "alloc")
        #expect(Self.retainedFamily(of: "copyright") == nil)
        #expect(Self.retainedFamily(of: "newline") == nil)
        #expect(Self.retainedFamily(of: "duplicate") == nil)
        #expect(Self.retainedFamily(of: "croppedCopy:") == nil)
    }

    @Test("No JSExport method that returns an object is in a retained-result method family")
    func noRetainedFamilyMethods() throws {
        let jsExport = try #require(objc_getProtocol("JSExport"))
        var checked = 0
        var offenders: [String] = []
        for proto in try Self.appProtocols() {
            guard !protocol_isEqual(proto, jsExport), protocol_conformsToProtocol(proto, jsExport) else { continue }
            checked += 1
            let protoName = String(cString: protocol_getName(proto))
            for (isRequired, isInstance) in [(true, true), (true, false), (false, true), (false, false)] {
                var methodCount: UInt32 = 0
                guard let methods = protocol_copyMethodDescriptionList(proto, isRequired, isInstance, &methodCount) else { continue }
                defer { free(methods) }
                for method in UnsafeBufferPointer(start: methods, count: Int(methodCount)) {
                    guard let selector = method.name else { continue }
                    let selectorName = NSStringFromSelector(selector)
                    if let family = Self.retainedFamily(of: selectorName), Self.returnsObject(method.types) {
                        offenders.append("\(protoName) \(isInstance ? "-" : "+")\(selectorName) (\(family) family)")
                    }
                }
            }
        }

        #expect(checked > 0, "Found no JSExport protocols to check")
        #expect(offenders.isEmpty, "JSExport methods in a retained-result method family leak every object they return to JS. Rename them: \(offenders.joined(separator: ", "))")
    }
}
