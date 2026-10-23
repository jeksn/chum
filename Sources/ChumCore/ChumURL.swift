import Foundation

public enum ChumURL {
    public enum Action: Equatable {
        case apply(name: String)
        case launcher
        case ephemeral(WindowCommand)
    }

    public static func parse(_ url: URL) -> Action? {
        guard url.scheme?.lowercased() == "chum" else { return nil }
        let host = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch host {
        case "launcher", "picker":
            return .launcher
        case "apply":
            guard let name = items.first(where: { $0.name.lowercased() == "name" })?.value, !name.isEmpty else { return nil }
            return .apply(name: name)
        case "command":
            return .ephemeral(ephemeralCommand(from: items))
        default:
            return nil
        }
    }

    public static func ephemeralCommand(from items: [URLQueryItem]) -> WindowCommand {
        var command = WindowCommand(name: "Temporary")

        if let position = items.first(where: { $0.name.lowercased() == "position" })?.value,
           let anchor = Anchor.named(position) {
            command.anchor = anchor
        }

        if let absolute = double(items, "absoluteWidth") {
            command.width = .points(absolute)
        } else if let relative = double(items, "relativeWidth") {
            command.width = .percent(relative * 100)
        }

        if let absolute = double(items, "absoluteHeight") {
            command.height = .points(absolute)
        } else if let relative = double(items, "relativeHeight") {
            command.height = .percent(relative * 100)
        }

        if let absolute = double(items, "absoluteXOffset") {
            command.offsetX = .points(absolute)
        } else if let relative = double(items, "relativeXOffset") {
            command.offsetX = .percent(relative * 100)
        }

        if let absolute = double(items, "absoluteYOffset") {
            command.offsetY = .points(absolute)
        } else if let relative = double(items, "relativeYOffset") {
            command.offsetY = .percent(relative * 100)
        }

        return command
    }

    private static func double(_ items: [URLQueryItem], _ name: String) -> Double? {
        items.first(where: { $0.name.lowercased() == name.lowercased() })?.value.flatMap { Double($0) }
    }
}
