import Foundation

public extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

public enum AppSettings {
    public static let gapKey = "edgeGap"
    public static let cycleHalvesKey = "cycleHalves"
    public static let autoCheckUpdatesKey = "autoCheckUpdates"
    public static let clipboardHistorySizeKey = "clipboardHistorySize"
    public static let clipboardAutoClearKey = "clipboardAutoClearSeconds"
    public static let clipboardEnabledKey = "clipboardMonitorEnabled"
    public static let snippetsEnabledKey = "snippetsEnabled"
    public static let hyperKeyEnabledKey = "hyperKeyEnabled"
    public static let hyperSymbolKey = "hyperSymbol"
    public static let launcherSlightTransparencyKey = "launcherSlightTransparency"
    public static let launcherClipboardTabKey = "launcherClipboardTab"
    public static let launcherSnippetsTabKey = "launcherSnippetsTab"
    public static let scratchpadTextKey = "scratchpadText"
    public static let transformOrderKey = "transformOrder"
    public static let transformDisabledKey = "transformDisabled"
    public static let baseCurrencyKey = "baseCurrency"
    public static let preferredUnitsKey = "preferredUnits"
    public static let aiProviderKey = "aiProvider"
    public static let aiAPIKeyKey = "aiAPIKey"
    public static let aiModelKey = "aiModel"

    public static var gap: Double {
        UserDefaults.standard.double(forKey: gapKey)
    }

    /// True when repeated application of a half command steps its size
    /// through 1/2 → 1/3 → 2/3 (Settings → Window).
    public static var cycleHalves: Bool {
        UserDefaults.standard.object(forKey: cycleHalvesKey) as? Bool ?? false
    }

    public static var autoCheckUpdates: Bool {
        UserDefaults.standard.object(forKey: autoCheckUpdatesKey) as? Bool ?? true
    }

    public static var clipboardEnabled: Bool {
        UserDefaults.standard.object(forKey: clipboardEnabledKey) as? Bool ?? true
    }

    public static var snippetsEnabled: Bool {
        UserDefaults.standard.object(forKey: snippetsEnabledKey) as? Bool ?? false
    }

    public static var hyperKeyEnabled: Bool {
        UserDefaults.standard.object(forKey: hyperKeyEnabledKey) as? Bool ?? false
    }

    public static var hyperSymbol: Bool {
        UserDefaults.standard.object(forKey: hyperSymbolKey) as? Bool ?? true
    }

    /// True when the launcher background keeps a slight translucency
    /// (85% opacity); off renders the background fully opaque.
    public static var launcherSlightTransparency: Bool {
        if UserDefaults.standard.object(forKey: launcherSlightTransparencyKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: launcherSlightTransparencyKey)
    }

    public static var launcherClipboardTab: Bool {
        UserDefaults.standard.object(forKey: launcherClipboardTabKey) as? Bool ?? true
    }

    public static var launcherSnippetsTab: Bool {
        UserDefaults.standard.object(forKey: launcherSnippetsTabKey) as? Bool ?? true
    }

    /// Base currency for launcher currency conversions (ISO code).
    public static var baseCurrency: String {
        let value = UserDefaults.standard.string(forKey: baseCurrencyKey) ?? "USD"
        return Calculator.supportedCurrencies.contains(value) ? value : "USD"
    }

    /// "metric" or "imperial" — the system bare-unit launcher queries
    /// convert into.
    public static var preferredUnits: String {
        UserDefaults.standard.string(forKey: preferredUnitsKey) ?? "metric"
    }

    /// The user's chosen transformation order (Settings → Text Transformer).
    /// Stored rawValues that no longer exist are dropped; transforms missing
    /// from the stored order (added in later releases) append at the end.
    public static var transformOrder: [String] {
        let known = TextTransform.allCases.map(\.rawValue)
        let stored = UserDefaults.standard.stringArray(forKey: transformOrderKey) ?? []
        var result = stored.filter { known.contains($0) }
        result.append(contentsOf: known.filter { !result.contains($0) })
        return result
    }

    public static var disabledTransforms: [String] {
        UserDefaults.standard.stringArray(forKey: transformDisabledKey) ?? []
    }

    /// The enabled transformations in the user's order — the list the Text
    /// Transformer tool shows.
    public static var orderedTransforms: [TextTransform] {
        let order = transformOrder
        let disabled = Set(disabledTransforms)
        var result = order.compactMap { raw -> TextTransform? in
            guard let transform = TextTransform(rawValue: raw), !disabled.contains(raw) else { return nil }
            return transform
        }
        result.append(contentsOf: TextTransform.allCases.filter {
            !order.contains($0.rawValue) && !disabled.contains($0.rawValue)
        })
        return result
    }

    public static func saveTransformOrder(_ rawValues: [String]) {
        UserDefaults.standard.set(rawValues, forKey: transformOrderKey)
    }

    public static func saveDisabledTransforms(_ rawValues: [String]) {
        UserDefaults.standard.set(rawValues, forKey: transformDisabledKey)
    }

    /// BYOK provider id for the (upcoming) AI Chat tool ("openai",
    /// "anthropic", "google", "mistral", "openrouter").
    public static var aiProvider: String {
        UserDefaults.standard.string(forKey: aiProviderKey) ?? "openai"
    }

    /// The model id for AI Chat requests; empty means the provider default.
    public static var aiModel: String {
        UserDefaults.standard.string(forKey: aiModelKey) ?? ""
    }
}
