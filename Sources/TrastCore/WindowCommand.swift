import Foundation

public enum WindowDimension: Hashable, Codable {
    case percent(Double)
    case points(Double)

    private enum CodingKeys: String, CodingKey {
        case percent
        case points
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(Double.self, forKey: .percent) {
            self = .percent(value)
        } else if let value = try container.decodeIfPresent(Double.self, forKey: .points) {
            self = .points(value)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a percent or points value"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .percent(let value): try container.encode(value, forKey: .percent)
        case .points(let value): try container.encode(value, forKey: .points)
        }
    }

    public var value: Double {
        switch self {
        case .percent(let value): return value
        case .points(let value): return value
        }
    }
}

public struct Anchor: Hashable {
    public enum Horizontal: String, Codable, CaseIterable {
        case left
        case center
        case right
        case keep
    }

    public enum Vertical: String, Codable, CaseIterable {
        case top
        case center
        case bottom
        case keep
    }

    public var horizontal: Horizontal
    public var vertical: Vertical

    public init(horizontal: Horizontal, vertical: Vertical) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let topLeft = Anchor(horizontal: .left, vertical: .top)
    public static let topCenter = Anchor(horizontal: .center, vertical: .top)
    public static let topRight = Anchor(horizontal: .right, vertical: .top)
    public static let middleLeft = Anchor(horizontal: .left, vertical: .center)
    public static let center = Anchor(horizontal: .center, vertical: .center)
    public static let middleRight = Anchor(horizontal: .right, vertical: .center)
    public static let bottomLeft = Anchor(horizontal: .left, vertical: .bottom)
    public static let bottomCenter = Anchor(horizontal: .center, vertical: .bottom)
    public static let bottomRight = Anchor(horizontal: .right, vertical: .bottom)
    public static let moveLeft = Anchor(horizontal: .left, vertical: .keep)
    public static let moveRight = Anchor(horizontal: .right, vertical: .keep)
    public static let moveUp = Anchor(horizontal: .keep, vertical: .top)
    public static let moveDown = Anchor(horizontal: .keep, vertical: .bottom)

    public static func named(_ rawValue: String) -> Anchor? {
        legacyNames[rawValue.lowercased()]
    }

    private static let legacyNames: [String: Anchor] = [
        "topleft": .topLeft,
        "topcenter": .topCenter,
        "topright": .topRight,
        "middleleft": .middleLeft,
        "center": .center,
        "middleright": .middleRight,
        "bottomleft": .bottomLeft,
        "bottomcenter": .bottomCenter,
        "bottomright": .bottomRight
    ]
}

extension Anchor: Codable {
    private enum CodingKeys: String, CodingKey {
        case horizontal
        case vertical
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            horizontal = try container.decode(Horizontal.self, forKey: .horizontal)
            vertical = try container.decode(Vertical.self, forKey: .vertical)
            return
        }

        let single = try decoder.singleValueContainer()
        let raw = try single.decode(String.self)
        guard let anchor = Anchor.named(raw) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown anchor \"\(raw)\""
                )
            )
        }
        self = anchor
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(horizontal, forKey: .horizontal)
        try container.encode(vertical, forKey: .vertical)
    }
}

public struct WindowCommand: Identifiable, Hashable {
    public var id = UUID()
    public var name = ""
    public var width: WindowDimension?
    public var height: WindowDimension?
    public var anchor = Anchor.topLeft
    public var offsetX = WindowDimension.percent(0)
    public var offsetY = WindowDimension.percent(0)
    public var isDefault = false
    public var showInMenuBar = false
    public var seedID: String?

    public init(
        id: UUID = UUID(),
        name: String = "",
        width: WindowDimension? = nil,
        height: WindowDimension? = nil,
        anchor: Anchor = .topLeft,
        offsetX: WindowDimension = .percent(0),
        offsetY: WindowDimension = .percent(0),
        isDefault: Bool = false,
        showInMenuBar: Bool = false,
        seedID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.anchor = anchor
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.isDefault = isDefault
        self.showInMenuBar = showInMenuBar
        self.seedID = seedID
    }

    public var defaultSeed: WindowCommand? {
        guard isDefault else { return nil }
        let key = seedID ?? name
        return WindowCommand.seeds.first { $0.name == key }
    }
}

extension WindowCommand: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case width
        case height
        case anchor
        case offsetX
        case offsetY
        case isDefault
        case showInMenuBar
        case seedID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        width = try container.decodeIfPresent(WindowDimension.self, forKey: .width)
        height = try container.decodeIfPresent(WindowDimension.self, forKey: .height)
        anchor = try container.decodeIfPresent(Anchor.self, forKey: .anchor) ?? .topLeft
        offsetX = try container.decodeIfPresent(WindowDimension.self, forKey: .offsetX) ?? .percent(0)
        offsetY = try container.decodeIfPresent(WindowDimension.self, forKey: .offsetY) ?? .percent(0)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? false
        seedID = try container.decodeIfPresent(String.self, forKey: .seedID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(height, forKey: .height)
        try container.encode(anchor, forKey: .anchor)
        try container.encode(offsetX, forKey: .offsetX)
        try container.encode(offsetY, forKey: .offsetY)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(showInMenuBar, forKey: .showInMenuBar)
        try container.encodeIfPresent(seedID, forKey: .seedID)
    }
}

extension WindowCommand {
    private static func seed(
        _ name: String,
        width: WindowDimension?,
        height: WindowDimension?,
        anchor: Anchor,
        offsetX: WindowDimension = .percent(0),
        offsetY: WindowDimension = .percent(0),
        showInMenuBar: Bool = false
    ) -> WindowCommand {
        WindowCommand(
            name: name,
            width: width,
            height: height,
            anchor: anchor,
            offsetX: offsetX,
            offsetY: offsetY,
            isDefault: true,
            showInMenuBar: showInMenuBar,
            seedID: name
        )
    }

    public static let seeds: [WindowCommand] = [
        seed("Left Half", width: .percent(50), height: .percent(100), anchor: .topLeft, showInMenuBar: true),
        seed("Right Half", width: .percent(50), height: .percent(100), anchor: .topRight, showInMenuBar: true),
        seed("Top Half", width: .percent(100), height: .percent(50), anchor: .topLeft),
        seed("Bottom Half", width: .percent(100), height: .percent(50), anchor: .bottomLeft),
        seed("Top Left Quarter", width: .percent(50), height: .percent(50), anchor: .topLeft),
        seed("Top Right Quarter", width: .percent(50), height: .percent(50), anchor: .topRight),
        seed("Bottom Left Quarter", width: .percent(50), height: .percent(50), anchor: .bottomLeft),
        seed("Bottom Right Quarter", width: .percent(50), height: .percent(50), anchor: .bottomRight),
        seed("First Fourth", width: .percent(25), height: .percent(100), anchor: .topLeft),
        seed("Second Fourth", width: .percent(25), height: .percent(100), anchor: .topLeft, offsetX: .percent(25)),
        seed("Third Fourth", width: .percent(25), height: .percent(100), anchor: .topLeft, offsetX: .percent(50)),
        seed("Last Fourth", width: .percent(25), height: .percent(100), anchor: .topRight),
        seed("First Third", width: .percent(100.0 / 3.0), height: .percent(100), anchor: .topLeft),
        seed("Center Third", width: .percent(100.0 / 3.0), height: .percent(100), anchor: .topCenter),
        seed("Last Third", width: .percent(100.0 / 3.0), height: .percent(100), anchor: .topRight),
        seed("First Two Thirds", width: .percent(200.0 / 3.0), height: .percent(100), anchor: .topLeft),
        seed("Last Two Thirds", width: .percent(200.0 / 3.0), height: .percent(100), anchor: .topRight),
        seed("Top Left Sixth", width: .percent(100.0 / 3.0), height: .percent(50), anchor: .topLeft),
        seed("Top Center Sixth", width: .percent(100.0 / 3.0), height: .percent(50), anchor: .topCenter),
        seed("Top Right Sixth", width: .percent(100.0 / 3.0), height: .percent(50), anchor: .topRight),
        seed("Bottom Left Sixth", width: .percent(100.0 / 3.0), height: .percent(50), anchor: .bottomLeft),
        seed("Bottom Center Sixth", width: .percent(100.0 / 3.0), height: .percent(50), anchor: .bottomCenter),
        seed("Bottom Right Sixth", width: .percent(100.0 / 3.0), height: .percent(50), anchor: .bottomRight),
        seed("Maximize", width: .percent(100), height: .percent(100), anchor: .topLeft, showInMenuBar: true),
        seed("Maximize Height", width: nil, height: .percent(100), anchor: Anchor(horizontal: .keep, vertical: .top)),
        seed("Maximize Width", width: .percent(100), height: nil, anchor: Anchor(horizontal: .left, vertical: .keep)),
        seed("Reasonable Size", width: .percent(60), height: .percent(60), anchor: .center)
    ]
}

extension WindowCommand {
    /// Fractions (percent) a half layout steps through on repeated
    /// application: 1/2 → 1/3 → 2/3.
    public static let halfCycleFractions: [Double] = [50, 100.0 / 3.0, 200.0 / 3.0]

    public enum HalfCycleAxis {
        case width
        case height
    }

    /// The axis a half command cycles on — `.width` for left/right halves,
    /// `.height` for top/bottom halves — or nil when the command is not a
    /// half layout (quarters, fourths, thirds, and custom sizes don't cycle).
    public var halfCycleAxis: HalfCycleAxis? {
        if width == .percent(50), height == .percent(100) { return .width }
        if width == .percent(100), height == .percent(50) { return .height }
        return nil
    }

    /// The command with its half-dimension replaced by the cycle fraction at
    /// `step` (wrapped). Commands that are not half layouts return self.
    public func cycledHalf(atStep step: Int) -> WindowCommand {
        guard let axis = halfCycleAxis else { return self }
        let count = Self.halfCycleFractions.count
        let fraction = Self.halfCycleFractions[((step % count) + count) % count]
        var cycled = self
        switch axis {
        case .width: cycled.width = .percent(fraction)
        case .height: cycled.height = .percent(fraction)
        }
        return cycled
    }
}

public struct LegacyMigrationResult {
    public let commands: [WindowCommand]
    public let droppedActionIDs: [String: UUID]

    init(commands: [WindowCommand], droppedActionIDs: [String: UUID]) {
        self.commands = commands
        self.droppedActionIDs = droppedActionIDs
    }
}

extension WindowCommand {
    public static func migratingLegacyCommands(_ legacy: [WindowCommand]) -> LegacyMigrationResult {
        var preservedIDsByName = [String: UUID]()
        var droppedActionIDs = [String: UUID]()
        var customs: [WindowCommand] = []

        for command in legacy {
            if let action = WindowAction.all.first(where: { $0.name == command.name }) {
                droppedActionIDs[action.id] = command.id
            } else if seeds.contains(where: { $0.name == command.name }) {
                preservedIDsByName[command.name] = command.id
            } else {
                var custom = command
                custom.isDefault = false
                custom.showInMenuBar = true
                customs.append(custom)
            }
        }

        let defaults = seeds.map { seed -> WindowCommand in
            var migrated = seed
            if let id = preservedIDsByName[seed.name] {
                migrated.id = id
            }
            return migrated
        }

        return LegacyMigrationResult(commands: defaults + customs, droppedActionIDs: droppedActionIDs)
    }
}

public struct WindowAction: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let anchor: Anchor
    public let commandID: UUID

    public init(id: String, name: String, anchor: Anchor, commandID: UUID) {
        self.id = id
        self.name = name
        self.anchor = anchor
        self.commandID = commandID
    }

    public var command: WindowCommand {
        WindowCommand(id: commandID, name: name, width: nil, height: nil, anchor: anchor)
    }

    public static let all: [WindowAction] = [
        WindowAction(id: "center", name: "Center", anchor: .center, commandID: UUID(uuidString: "A1000000-0000-4000-8000-0000000000A1")!),
        WindowAction(id: "moveLeft", name: "Move Left", anchor: .moveLeft, commandID: UUID(uuidString: "A1000000-0000-4000-8000-0000000000A2")!),
        WindowAction(id: "moveRight", name: "Move Right", anchor: .moveRight, commandID: UUID(uuidString: "A1000000-0000-4000-8000-0000000000A3")!),
        WindowAction(id: "moveUp", name: "Move Up", anchor: .moveUp, commandID: UUID(uuidString: "A1000000-0000-4000-8000-0000000000A4")!),
        WindowAction(id: "moveDown", name: "Move Down", anchor: .moveDown, commandID: UUID(uuidString: "A1000000-0000-4000-8000-0000000000A5")!),
        WindowAction(id: "nextDisplay", name: "Next Display", anchor: .center, commandID: UUID(uuidString: "A1000000-0000-4000-8000-0000000000A6")!)
    ]

    public static let nextDisplay = WindowAction(
        id: "nextDisplay",
        name: "Next Display",
        anchor: .center,
        commandID: UUID(uuidString: "A1000000-0000-4000-8000-0000000000A6")!
    )
}
