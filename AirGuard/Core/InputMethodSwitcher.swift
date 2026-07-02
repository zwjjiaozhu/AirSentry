import Carbon.HIToolbox
import Foundation

enum InputMethodSwitcher {
    static func selectableInputSources() -> [InputMethodSource] {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }

        return sources.compactMap { source in
            guard isSelectCapable(source),
                  let id = stringProperty(kTISPropertyInputSourceID, from: source),
                  let name = stringProperty(kTISPropertyLocalizedName, from: source) else {
                return nil
            }
            return InputMethodSource(id: id, name: name)
        }
        .sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    @discardableResult
    static func selectInputSource(id: String) -> Bool {
        let properties = [kTISPropertyInputSourceID: id] as CFDictionary
        guard let matches = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource],
              let source = matches.first else {
            return false
        }

        return TISSelectInputSource(source) == noErr
    }

    private static func isSelectCapable(_ source: TISInputSource) -> Bool {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else {
            return false
        }
        guard let boolValue = Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue() as? Bool else {
            return false
        }
        return boolValue
    }

    private static func stringProperty(_ key: CFString, from source: TISInputSource) -> String? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue() as? String
    }
}
