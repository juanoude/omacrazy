import Foundation

enum ZedAdapter {
    private struct LocalTheme {
        let source: URL
        let selectableName: String
    }

    static func apply(themeRoot: URL) throws -> String? {
        guard let theme = try discoverTheme(in: themeRoot) else { return nil }

        let fileManager = FileManager.default
        let configRoot: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            configRoot = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            configRoot = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
        }

        let zedDirectory = configRoot.appendingPathComponent("zed", isDirectory: true)
        let themesDirectory = zedDirectory.appendingPathComponent("themes", isDirectory: true)
        let settingsFile = zedDirectory.appendingPathComponent("settings.json")
        let destination = themesDirectory.appendingPathComponent(theme.source.lastPathComponent)

        try fileManager.createDirectory(at: themesDirectory, withIntermediateDirectories: true)
        try preserveAndWrite(source: theme.source, destination: destination)

        let originalSettings = fileManager.fileExists(atPath: settingsFile.path)
            ? try String(contentsOf: settingsFile, encoding: .utf8)
            : "{}\n"
        let updatedSettings = try ZedSettingsEditor.settingTheme(theme.selectableName, in: originalSettings)
        if updatedSettings != originalSettings {
            if fileManager.fileExists(atPath: settingsFile.path) {
                let backup = zedDirectory.appendingPathComponent("settings.json.omacrazy-backup")
                if !fileManager.fileExists(atPath: backup.path) {
                    try fileManager.copyItem(at: settingsFile, to: backup)
                }
            }
            try Data(updatedSettings.utf8).write(to: settingsFile, options: .atomic)
        }

        return "installed '\(theme.selectableName)' locally and selected it in settings.json"
    }

    static func hasTheme(themeRoot: URL) throws -> Bool {
        try discoverTheme(in: themeRoot) != nil
    }

    private static func discoverTheme(in themeRoot: URL) throws -> LocalTheme? {
        let fileManager = FileManager.default
        let extensionDirectory = themeRoot.appendingPathComponent("zed/themes", isDirectory: true)
        let extensionThemes = try jsonFiles(in: extensionDirectory)
        let sourceFiles: [URL]
        if !extensionThemes.isEmpty {
            sourceFiles = extensionThemes
        } else {
            let standalone = themeRoot.appendingPathComponent("zed.json")
            sourceFiles = fileManager.fileExists(atPath: standalone.path) ? [standalone] : []
        }

        for source in sourceFiles {
            let data = try Data(contentsOf: source)
            let root = try JSONSerialization.jsonObject(with: data)
            guard let family = root as? [String: Any],
                  let themes = family["themes"] as? [[String: Any]] else {
                throw OmacrazyError(description: "\(source.lastPathComponent) is not a valid Zed theme family JSON")
            }
            if let dark = themes.first(where: { ($0["appearance"] as? String) == "dark" }),
               let name = dark["name"] as? String {
                return LocalTheme(source: source, selectableName: name)
            }
            if let first = themes.first, let name = first["name"] as? String {
                return LocalTheme(source: source, selectableName: name)
            }
            throw OmacrazyError(description: "\(source.lastPathComponent) contains no named Zed themes")
        }
        return nil
    }

    private static func jsonFiles(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension.lowercased() == "json" }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func preserveAndWrite(source: URL, destination: URL) throws {
        let sourceData = try Data(contentsOf: source)
        if FileManager.default.fileExists(atPath: destination.path) {
            if try Data(contentsOf: destination) == sourceData { return }
            let backup = destination.appendingPathExtension("omacrazy-backup")
            if !FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.copyItem(at: destination, to: backup)
            }
            try sourceData.write(to: destination, options: .atomic)
        } else {
            try sourceData.write(to: destination, options: .atomic)
        }
    }
}

/// Replaces or adds only the root-level `theme` setting while leaving JSONC comments
/// and all other settings text untouched.
private enum ZedSettingsEditor {
    static func settingTheme(_ name: String, in source: String) throws -> String {
        let replacement = try JSONEncoder().encode(name)
        var parser = JSONCObjectParser(source)
        let object = try parser.rootObject()
        let replacementText = String(decoding: replacement, as: UTF8.self)

        if let valueRange = object.themeValueRange {
            var bytes = Array(source.utf8)
            bytes.replaceSubrange(valueRange, with: replacement)
            return String(decoding: bytes, as: UTF8.self)
        }

        var bytes = Array(source.utf8)
        if !object.isEmpty && !object.lastMemberHasComma {
            bytes.insert(0x2C, at: object.lastValueEnd)
        }
        let closeIndex = object.closeBrace + ((!object.isEmpty && !object.lastMemberHasComma) ? 1 : 0)
        let addedSetting = "\n  \"theme\": \(replacementText)\n"
        bytes.insert(contentsOf: addedSetting.utf8, at: closeIndex)
        return String(decoding: bytes, as: UTF8.self)
    }
}

private struct ParsedRootObject {
    let closeBrace: Int
    let themeValueRange: Range<Int>?
    let lastValueEnd: Int
    let lastMemberHasComma: Bool
    let isEmpty: Bool
}

private struct JSONCObjectParser {
    private let bytes: [UInt8]
    private var index = 0

    init(_ source: String) {
        self.bytes = Array(source.utf8)
    }

    mutating func rootObject() throws -> ParsedRootObject {
        skipTrivia()
        guard current == 0x7B else { throw invalidSettings() }
        index += 1
        skipTrivia()

        if current == 0x7D {
            return ParsedRootObject(closeBrace: index, themeValueRange: nil, lastValueEnd: index, lastMemberHasComma: false, isEmpty: true)
        }

        var lastValueEnd = index
        var themeValueRange: Range<Int>?
        while index < bytes.count {
            skipTrivia()
            guard current == 0x22, let keyEnd = scanString(from: index) else { throw invalidSettings() }
            let key = String(decoding: bytes[index..<keyEnd], as: UTF8.self)
            index = keyEnd
            skipTrivia()
            guard current == 0x3A else { throw invalidSettings() }
            index += 1
            skipTrivia()
            let valueStart = index
            let valueEnd = try scanValue(from: valueStart)
            lastValueEnd = valueEnd
            index = valueEnd

            if key == "\"theme\"" {
                themeValueRange = valueStart..<valueEnd
            }

            skipTrivia()
            if current == 0x2C {
                index += 1
                skipTrivia()
                if current == 0x7D {
                    return ParsedRootObject(closeBrace: index, themeValueRange: themeValueRange, lastValueEnd: lastValueEnd, lastMemberHasComma: true, isEmpty: false)
                }
            } else if current == 0x7D {
                return ParsedRootObject(closeBrace: index, themeValueRange: themeValueRange, lastValueEnd: lastValueEnd, lastMemberHasComma: false, isEmpty: false)
            } else {
                throw invalidSettings()
            }
        }
        throw invalidSettings()
    }

    private var current: UInt8? { index < bytes.count ? bytes[index] : nil }

    private mutating func skipTrivia() {
        while index < bytes.count {
            if bytes[index] == 0x20 || bytes[index] == 0x09 || bytes[index] == 0x0A || bytes[index] == 0x0D {
                index += 1
            } else if index + 1 < bytes.count && bytes[index] == 0x2F && bytes[index + 1] == 0x2F {
                index += 2
                while index < bytes.count && bytes[index] != 0x0A && bytes[index] != 0x0D { index += 1 }
            } else if index + 1 < bytes.count && bytes[index] == 0x2F && bytes[index + 1] == 0x2A {
                index += 2
                while index + 1 < bytes.count && !(bytes[index] == 0x2A && bytes[index + 1] == 0x2F) { index += 1 }
                index = min(index + 2, bytes.count)
            } else {
                break
            }
        }
    }

    private func scanString(from start: Int) -> Int? {
        guard start < bytes.count && bytes[start] == 0x22 else { return nil }
        var cursor = start + 1
        while cursor < bytes.count {
            if bytes[cursor] == 0x5C {
                cursor += 2
            } else if bytes[cursor] == 0x22 {
                return cursor + 1
            } else {
                cursor += 1
            }
        }
        return nil
    }

    private func scanValue(from start: Int) throws -> Int {
        guard start < bytes.count else { throw invalidSettings() }
        if bytes[start] == 0x22 {
            guard let end = scanString(from: start) else { throw invalidSettings() }
            return end
        }
        if bytes[start] == 0x7B || bytes[start] == 0x5B {
            var stack: [UInt8] = [bytes[start] == 0x7B ? 0x7D : 0x5D]
            var cursor = start + 1
            while cursor < bytes.count {
                if bytes[cursor] == 0x22 {
                    guard let end = scanString(from: cursor) else { throw invalidSettings() }
                    cursor = end
                } else if cursor + 1 < bytes.count && bytes[cursor] == 0x2F && (bytes[cursor + 1] == 0x2F || bytes[cursor + 1] == 0x2A) {
                    cursor = skipComment(from: cursor)
                } else if bytes[cursor] == 0x7B {
                    stack.append(0x7D); cursor += 1
                } else if bytes[cursor] == 0x5B {
                    stack.append(0x5D); cursor += 1
                } else if bytes[cursor] == 0x7D || bytes[cursor] == 0x5D {
                    guard stack.last == bytes[cursor] else { throw invalidSettings() }
                    stack.removeLast()
                    cursor += 1
                    if stack.isEmpty { return cursor }
                } else {
                    cursor += 1
                }
            }
            throw invalidSettings()
        }

        var cursor = start
        while cursor < bytes.count {
            if bytes[cursor] == 0x2C || bytes[cursor] == 0x7D { break }
            if cursor + 1 < bytes.count && bytes[cursor] == 0x2F && (bytes[cursor + 1] == 0x2F || bytes[cursor + 1] == 0x2A) { break }
            cursor += 1
        }
        while cursor > start && (bytes[cursor - 1] == 0x20 || bytes[cursor - 1] == 0x09 || bytes[cursor - 1] == 0x0A || bytes[cursor - 1] == 0x0D) { cursor -= 1 }
        guard cursor > start else { throw invalidSettings() }
        return cursor
    }

    private func skipComment(from start: Int) -> Int {
        var cursor = start + 2
        if bytes[start + 1] == 0x2F {
            while cursor < bytes.count && bytes[cursor] != 0x0A && bytes[cursor] != 0x0D { cursor += 1 }
            return cursor
        }
        while cursor + 1 < bytes.count && !(bytes[cursor] == 0x2A && bytes[cursor + 1] == 0x2F) { cursor += 1 }
        return min(cursor + 2, bytes.count)
    }

    private func invalidSettings() -> OmacrazyError {
        OmacrazyError(description: "Zed settings.json is not a valid JSONC object")
    }
}
