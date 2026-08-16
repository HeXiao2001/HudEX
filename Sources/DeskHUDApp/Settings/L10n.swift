import Foundation

/// Localized string lookup in the SPM resources bundle (`Bundle.module`).
/// Keys are the English source strings; zh-Hans lives in
/// `Resources/zh-Hans.lproj/Localizable.strings`.
func tr(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}
