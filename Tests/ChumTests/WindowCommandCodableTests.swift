import Foundation
import ChumCore

enum WindowCommandCodableTests {
    static func runAll(_ t: TestRunner) {
        t.run("Codable.dimensionRoundTrip") {
            let dimensions: [WindowDimension] = [.percent(50), .points(512), .percent(-10)]
            for dimension in dimensions {
                let data = try JSONEncoder().encode(dimension)
                let decoded = try JSONDecoder().decode(WindowDimension.self, from: data)
                t.check(decoded == dimension, "round trip failed for \(dimension)")
            }
        }

        t.run("Codable.dimensionEncodingShape") {
            let data = try JSONEncoder().encode(WindowDimension.percent(50))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Double]
            t.check(json == ["percent": 50], "got \(String(describing: json))")
        }

        t.run("Codable.dimensionDecodingRejectsEmptyObject") {
            t.expectThrows("empty object should not decode") {
                _ = try JSONDecoder().decode(WindowDimension.self, from: Data("{}".utf8))
            }
        }

        t.run("Codable.commandRoundTrip") {
            var command = WindowCommand(name: "Left Half", width: .percent(50), height: .percent(100), anchor: .topRight)
            command.offsetX = .points(-20)
            command.offsetY = .percent(5)
            let data = try JSONEncoder().encode(command)
            let decoded = try JSONDecoder().decode(WindowCommand.self, from: data)
            t.check(decoded == command, "round trip mismatch")
        }

        t.run("Codable.nilDimensionsRoundTrip") {
            let command = WindowCommand(name: "Center", width: nil, height: nil, anchor: .center)
            let data = try JSONEncoder().encode(command)
            let decoded = try JSONDecoder().decode(WindowCommand.self, from: data)
            t.check(decoded.width == nil, "width should be nil")
            t.check(decoded.height == nil, "height should be nil")
            t.check(decoded.anchor == .center, "anchor mismatch")
        }

        t.run("Codable.seedCommandsDecode") {
            let data = try JSONEncoder().encode(WindowCommand.seeds)
            let decoded = try JSONDecoder().decode([WindowCommand].self, from: data)
            t.check(decoded.count == WindowCommand.seeds.count, "count mismatch")
            t.check(decoded == WindowCommand.seeds, "seed round trip mismatch")
        }

        t.run("Codable.anchorLegacyStringDecodes") {
            let decoded = try JSONDecoder().decode(Anchor.self, from: Data("\"topLeft\"".utf8))
            t.check(decoded == .topLeft, "got \(decoded)")
            let center = try JSONDecoder().decode(Anchor.self, from: Data("\"center\"".utf8))
            t.check(center == .center, "got \(center)")
        }

        t.run("Codable.anchorKeyedRoundTrip") {
            let anchor = Anchor(horizontal: .keep, vertical: .bottom)
            let data = try JSONEncoder().encode(anchor)
            let decoded = try JSONDecoder().decode(Anchor.self, from: data)
            t.check(decoded == anchor, "got \(decoded)")
        }

        t.run("Codable.anchorEncodingShape") {
            let data = try JSONEncoder().encode(Anchor.topLeft)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
            t.check(json == ["horizontal": "left", "vertical": "top"], "got \(String(describing: json))")
        }

        t.run("Codable.commandDecodesWithoutNewFields") {
            let json = #"{"name": "Left Half", "anchor": "topLeft", "width": {"percent": 50}, "height": {"percent": 100}}"#
            let decoded = try JSONDecoder().decode(WindowCommand.self, from: Data(json.utf8))
            t.check(decoded.isDefault == false, "isDefault should default to false")
            t.check(decoded.showInMenuBar == false, "showInMenuBar should default to false")
            t.check(decoded.anchor == .topLeft, "anchor mismatch")
        }

        t.run("Migration.legacySeedSetBecomesDefaultsPreservingIDs") {
            let legacyID = UUID()
            let legacy: [WindowCommand] = [
                WindowCommand(id: legacyID, name: "Left Half", width: .percent(50), height: .percent(100), anchor: .topLeft),
                WindowCommand(name: "Right Half", width: .percent(50), height: .percent(100), anchor: .topRight),
                WindowCommand(name: "Center", width: .percent(60), height: .percent(60), anchor: .center),
                WindowCommand(name: "Top Left Quarter", width: .percent(50), height: .percent(50), anchor: .topLeft),
                WindowCommand(name: "Maximize", width: .percent(100), height: .percent(100), anchor: .topLeft)
            ]

            let result = WindowCommand.migratingLegacyCommands(legacy)
            t.check(result.commands.count == WindowCommand.seeds.count, "expected full seed set, got \(result.commands.count)")
            t.check(result.commands.allSatisfy(\.isDefault), "all migrated commands should be defaults")
            let leftHalf = result.commands.first { $0.name == "Left Half" }
            t.check(leftHalf?.id == legacyID, "hotkey-bound id should be preserved")
            t.check(result.commands.first { $0.name == "Center" } == nil, "Center should become an action, not a command")
            t.check(result.droppedActionIDs["center"] != nil, "Center should be reported as a dropped action")
        }

        t.run("Migration.legacyCustomCommandsArePreserved") {
            let legacy: [WindowCommand] = [
                WindowCommand(name: "Left Half", width: .percent(50), height: .percent(100), anchor: .topLeft),
                WindowCommand(name: "My Custom", width: .points(500), height: nil, anchor: .middleLeft)
            ]

            let result = WindowCommand.migratingLegacyCommands(legacy)
            let custom = result.commands.first { $0.name == "My Custom" }
            t.check(custom != nil, "custom command should survive")
            t.check(custom?.isDefault == false, "custom should stay custom")
            t.check(custom?.showInMenuBar == true, "custom should be pinned to menu bar")
            t.check(result.commands.contains { $0.name == "Maximize" }, "missing defaults should be added")
        }

        t.run("Migration.legacyMoveCommandsBecomeActions") {
            let moveID = UUID()
            let legacy: [WindowCommand] = [
                WindowCommand(id: moveID, name: "Move Left", width: nil, height: nil, anchor: .moveLeft)
            ]

            let result = WindowCommand.migratingLegacyCommands(legacy)
            t.check(result.commands.first { $0.name == "Move Left" } == nil, "move commands should be dropped from the command list")
            t.check(result.droppedActionIDs["moveLeft"] == moveID, "move hotkey id should be reported for remapping")
        }

        t.run("Actions.fixedList") {
            t.check(WindowAction.all.count == 6, "expected 6 actions")
            t.check(WindowAction.all.allSatisfy({ $0.command.width == nil && $0.command.height == nil }), "actions should keep window size")
            let center = WindowAction.all.first { $0.id == "center" }
            t.check(center?.anchor == .center, "center anchor mismatch")
            let nextDisplay = WindowAction.all.first { $0.id == "nextDisplay" }
            t.check(nextDisplay != nil, "nextDisplay action missing")
        }

        t.run("DefaultSeed.resolvesBySeedIDAndName") {
            var command = WindowCommand(name: "Left Half", width: .percent(10), height: .percent(10), anchor: .center, isDefault: true)
            t.check(command.defaultSeed?.name == "Left Half", "seed lookup by name fallback failed")

            command.seedID = "Left Half"
            let seed = command.defaultSeed
            t.check(seed?.name == "Left Half", "seed lookup by seedID failed")

            let renamed = WindowCommand(name: "Left", width: .percent(10), height: .percent(10), anchor: .center, isDefault: true, seedID: "Left Half")
            t.check(renamed.defaultSeed?.name == "Left Half", "renamed default should still resolve its seed")

            let custom = WindowCommand(name: "Mine", isDefault: false)
            t.check(custom.defaultSeed == nil, "customs have no default seed")
        }

        t.run("HalfCycle.axisDetection") {
            let leftHalf = WindowCommand(name: "Left Half", width: .percent(50), height: .percent(100), anchor: .topLeft)
            t.check(leftHalf.halfCycleAxis == .width, "left half should cycle width")
            let topHalf = WindowCommand(name: "Top Half", width: .percent(100), height: .percent(50), anchor: .topLeft)
            t.check(topHalf.halfCycleAxis == .height, "top half should cycle height")
            let quarter = WindowCommand(name: "Top Left Quarter", width: .percent(50), height: .percent(50), anchor: .topLeft)
            t.check(quarter.halfCycleAxis == nil, "quarters should not cycle")
            let third = WindowCommand(name: "First Third", width: .percent(100.0 / 3.0), height: .percent(100), anchor: .topLeft)
            t.check(third.halfCycleAxis == nil, "thirds should not cycle")
            let maximize = WindowCommand(name: "Maximize", width: .percent(100), height: .percent(100), anchor: .topLeft)
            t.check(maximize.halfCycleAxis == nil, "maximize should not cycle")
        }

        t.run("HalfCycle.stepsThroughHalfThirdTwoThirds") {
            let rightHalf = WindowCommand(name: "Right Half", width: .percent(50), height: .percent(100), anchor: .topRight)
            let first = rightHalf.cycledHalf(atStep: 0)
            t.check(first.width == .percent(50), "step 0 should stay 1/2")
            let second = rightHalf.cycledHalf(atStep: 1)
            t.check(second.width == .percent(100.0 / 3.0), "step 1 should be 1/3")
            let third = rightHalf.cycledHalf(atStep: 2)
            t.check(third.width == .percent(200.0 / 3.0), "step 2 should be 2/3")
            let wrapped = rightHalf.cycledHalf(atStep: 3)
            t.check(wrapped.width == .percent(50), "step 3 should wrap to 1/2")
            t.check(second.anchor == .topRight && second.height == .percent(100), "cycling should keep the anchor and other dimension")
        }

        t.run("HalfCycle.topHalfCyclesHeight") {
            let bottomHalf = WindowCommand(name: "Bottom Half", width: .percent(100), height: .percent(50), anchor: .bottomLeft)
            t.check(bottomHalf.cycledHalf(atStep: 1).height == .percent(100.0 / 3.0), "bottom half step 1 height mismatch")
            t.check(bottomHalf.cycledHalf(atStep: 2).height == .percent(200.0 / 3.0), "bottom half step 2 height mismatch")
        }

        t.run("HalfCycle.nonHalfReturnsSelf") {
            let maximize = WindowCommand(name: "Maximize", width: .percent(100), height: .percent(100), anchor: .topLeft)
            t.check(maximize.cycledHalf(atStep: 2) == maximize, "non-half command should be unchanged")
        }
    }
}
