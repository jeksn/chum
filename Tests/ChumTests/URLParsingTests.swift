import Foundation
import ChumCore

enum URLParsingTests {
    private static func parse(_ string: String) -> ChumURL.Action? {
        guard let url = URL(string: string) else { return nil }
        return ChumURL.parse(url)
    }

    static func runAll(_ t: TestRunner) {
        t.run("URLParsing.launcher") {
            t.check(parse("chum://launcher") == .launcher, "launcher not parsed")
            t.check(parse("chum://picker") == .launcher, "legacy picker should still work")
        }

        t.run("URLParsing.applyByName") {
            t.check(parse("chum://apply?name=Left%20Half") == .apply(name: "Left Half"), "apply not parsed")
        }

        t.run("URLParsing.applyWithoutNameIsRejected") {
            t.check(parse("chum://apply") == nil, "apply without name should be rejected")
        }

        t.run("URLParsing.wrongSchemeIsRejected") {
            t.check(parse("https://chum/launcher") == nil, "https should be rejected")
            t.check(parse("raycast://launcher") == nil, "raycast scheme should be rejected")
        }

        t.run("URLParsing.unknownHostIsRejected") {
            t.check(parse("chum://bogus") == nil, "unknown host should be rejected")
        }

        t.run("URLParsing.ephemeralRelativeSizeAndPosition") {
            guard case .ephemeral(let command)? = parse("chum://command?position=center&relativeWidth=0.5&relativeHeight=0.5") else {
                t.check(false, "expected ephemeral action")
                return
            }
            t.check(command.anchor == .center, "anchor \(command.anchor)")
            t.check(command.width == .percent(50), "width \(String(describing: command.width))")
            t.check(command.height == .percent(50), "height \(String(describing: command.height))")
        }

        t.run("URLParsing.ephemeralAbsoluteSizeAndOffsets") {
            guard case .ephemeral(let command)? = parse("chum://command?absoluteWidth=500&relativeXOffset=-0.1&absoluteYOffset=40") else {
                t.check(false, "expected ephemeral action")
                return
            }
            t.check(command.width == .points(500), "width \(String(describing: command.width))")
            t.check(command.offsetX == .percent(-10), "offsetX \(command.offsetX)")
            t.check(command.offsetY == .points(40), "offsetY \(command.offsetY)")
        }

        t.run("URLParsing.ephemeralDefaultsToTopLeftAnchor") {
            guard case .ephemeral(let command)? = parse("chum://command?relativeWidth=1") else {
                t.check(false, "expected ephemeral action")
                return
            }
            t.check(command.anchor == .topLeft, "anchor \(command.anchor)")
            t.check(command.width == .percent(100), "width \(String(describing: command.width))")
        }
    }
}
