import Foundation

/// The three app secrets. Values are read, in order, from:
/// 1. `Jojo/Config/Secrets.plist` (gitignored, copy `Config/Secrets.example.plist`)
/// 2. Build-time environment (`EXPO_PUBLIC_SUPABASE_URL`, … via Config.swift) if present
/// 3. Placeholder values, which the app detects and treats as "not configured" (fully offline mode).
nonisolated enum Secrets {
    static let placeholderPrefix = "YOUR_"

    static let supabaseURL: String = value("SUPABASE_URL", env: "EXPO_PUBLIC_SUPABASE_URL", placeholder: "YOUR_SUPABASE_URL")
    static let supabaseAnonKey: String = value("SUPABASE_ANON_KEY", env: "EXPO_PUBLIC_SUPABASE_ANON_KEY", placeholder: "YOUR_SUPABASE_ANON_KEY")
    /// RevenueCat public SDK key. DEBUG builds use the Test Store key; release builds use the App Store key.
    /// Prefer `REVENUECAT_TEST_API_KEY` / `REVENUECAT_IOS_API_KEY`. `REVENUECAT_API_KEY` overrides either.
    static let revenueCatAPIKey: String = {
        #if DEBUG
        return revenueCatValue(
            preferredKey: "REVENUECAT_TEST_API_KEY",
            env: "EXPO_PUBLIC_REVENUECAT_TEST_API_KEY"
        )
        #else
        return revenueCatValue(
            preferredKey: "REVENUECAT_IOS_API_KEY",
            env: "EXPO_PUBLIC_REVENUECAT_IOS_API_KEY"
        )
        #endif
    }()

    static var isSupabaseConfigured: Bool {
        isReal(supabaseURL) && isReal(supabaseAnonKey) && URL(string: supabaseURL) != nil
    }

    static var isRevenueCatConfigured: Bool { isReal(revenueCatAPIKey) }

    /// Meta / Facebook app credentials (public App ID + Client Token from Developers → Settings → Advanced).
    /// Used only for install attribution + `$fbAnonId`; purchases go through RevenueCat → Conversions API.
    static let metaAppID: String = value("META_APP_ID", env: "EXPO_PUBLIC_META_APP_ID", placeholder: "YOUR_META_APP_ID")
    static let metaClientToken: String = value("META_CLIENT_TOKEN", env: "EXPO_PUBLIC_META_CLIENT_TOKEN", placeholder: "YOUR_META_CLIENT_TOKEN")
    static var isMetaConfigured: Bool { isReal(metaAppID) && isReal(metaClientToken) }

    private static func isReal(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix(placeholderPrefix)
    }

    private static let plist: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return dict
    }()

    private static func value(_ key: String, env: String, placeholder: String) -> String {
        if let v = plist[key] as? String, isReal(v) { return v }
        if let v = Config.allValues[env], isReal(v) { return v }
        return placeholder
    }

    private static func revenueCatValue(preferredKey: String, env: String) -> String {
        if let override = plist["REVENUECAT_API_KEY"] as? String, isReal(override) { return override }
        if let preferred = plist[preferredKey] as? String, isReal(preferred) { return preferred }
        if let fromEnv = Config.allValues[env], isReal(fromEnv) { return fromEnv }
        return "YOUR_REVENUECAT_API_KEY"
    }
}
