import Foundation

struct OmacrazyError: Error, CustomStringConvertible {
    let description: String
}

@main
enum Omacrazy {
    @MainActor
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("omacrazy: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    @MainActor
    static func run(arguments: [String]) throws {
        guard arguments.count == 2, arguments[0] == "theme" else {
            print("Usage: omacrazy theme <name>")
            if !arguments.isEmpty { throw OmacrazyError(description: "unsupported command") }
            return
        }

        let themeName = arguments[1]
        guard themeName.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil else {
            throw OmacrazyError(description: "invalid theme name '\(themeName)'")
        }

        let themeRoot = try ThemeLocator.findTheme(named: themeName)
        var succeeded = 0
        var failed = 0

        let ghosttySource = themeRoot.appendingPathComponent("ghostty.conf")
        if FileManager.default.fileExists(atPath: ghosttySource.path) {
            do {
                try GhosttyAdapter.apply(themeName: themeName, source: ghosttySource)
                print("Ghostty: applied '\(themeName)' (reload with Cmd+Shift+Comma).")
                succeeded += 1
            } catch {
                fputs("Ghostty: failed: \(error)\n", stderr)
                failed += 1
            }
        } else {
            print("Ghostty: skipped (theme has no ghostty.conf).")
        }

        let hyprlandSource = themeRoot.appendingPathComponent("hyprland.conf")
        if FileManager.default.fileExists(atPath: hyprlandSource.path) {
            do {
                let colors = try HyprlandActiveBorder.read(from: hyprlandSource)
                let result = try JankyBordersAdapter.apply(colors: colors)
                print("JankyBorders: \(result)")
                succeeded += 1
            } catch {
                fputs("JankyBorders: failed: \(error)\n", stderr)
                failed += 1
            }
        } else {
            print("JankyBorders: skipped (theme has no Hyprland active border color).")
        }

        do {
            if let result = try ZedAdapter.apply(themeRoot: themeRoot) {
                print("Zed: \(result).")
                succeeded += 1
            } else {
                print("Zed: skipped (theme has no Zed theme JSON).")
            }
        } catch {
            fputs("Zed: failed: \(error)\n", stderr)
            failed += 1
        }

        do {
            if let result = try WallpaperAdapter.apply(themeName: themeName, themeRoot: themeRoot) {
                print("Wallpaper: applied '\(result.imageName)' to \(result.screenCount) display(s).")
                succeeded += 1
            } else {
                print("Wallpaper: skipped (theme has no images in its backgrounds/ folder).")
            }
        } catch {
            fputs("Wallpaper: failed: \(error)\n", stderr)
            failed += 1
        }

        if failed > 0 || succeeded == 0 {
            throw OmacrazyError(description: "theme application finished with \(succeeded) target(s) applied and \(failed) failure(s)")
        }
    }
}

enum ThemeLocator {
    static func findTheme(named name: String) throws -> URL {
        let fileManager = FileManager.default
        let candidates = [URL(fileURLWithPath: fileManager.currentDirectoryPath)] +
            [URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL]

        for start in candidates {
            var directory = start
            if !directory.hasDirectoryPath { directory.deleteLastPathComponent() }
            while true {
                let candidate = directory.appendingPathComponent("themes", isDirectory: true)
                    .appendingPathComponent(name, isDirectory: true)
                if fileManager.fileExists(atPath: candidate.path) { return candidate }
                let parent = directory.deletingLastPathComponent()
                if parent.path == directory.path { break }
                directory = parent
            }
        }

        throw OmacrazyError(description: "theme '\(name)' not found under a themes/ directory")
    }
}

enum GhosttyAdapter {
    private static let beginMarker = "# BEGIN OMACRAZY THEME"
    private static let endMarker = "# END OMACRAZY THEME"

    static func apply(themeName: String, source: URL) throws {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let configDirectory: URL
        if let override = ProcessInfo.processInfo.environment["OMACRAZY_GHOSTTY_CONFIG_DIR"], !override.isEmpty {
            configDirectory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            configDirectory = home.appendingPathComponent("Library/Application Support/com.mitchellh.ghostty", isDirectory: true)
        }

        // Ghostty loads the legacy `config` after `config.ghostty` when both exist.
        // Reuse it when present so the managed include remains effective.
        let legacyConfig = configDirectory.appendingPathComponent("config")
        let modernConfig = configDirectory.appendingPathComponent("config.ghostty")
        let configFile = fileManager.fileExists(atPath: legacyConfig.path) ? legacyConfig : modernConfig
        let themeDirectory = configDirectory.appendingPathComponent("omacrazy/themes", isDirectory: true)
        let installedTheme = themeDirectory.appendingPathComponent("\(themeName).conf")

        let themeContents = try String(contentsOf: source, encoding: .utf8)
        try fileManager.createDirectory(at: themeDirectory, withIntermediateDirectories: true)
        try atomicWrite(themeContents, to: installedTheme)

        let existingConfig: String
        if fileManager.fileExists(atPath: configFile.path) {
            existingConfig = try String(contentsOf: configFile, encoding: .utf8)
            let backup = configDirectory.appendingPathComponent(configFile.lastPathComponent + ".omacrazy-backup")
            if !fileManager.fileExists(atPath: backup.path) {
                try fileManager.copyItem(at: configFile, to: backup)
            }
        } else {
            existingConfig = ""
        }

        let configWithoutManagedBlock = removingManagedBlock(from: existingConfig)
        let relativeThemePath = "omacrazy/themes/\(themeName).conf"
        let managedBlock = "\(beginMarker)\nconfig-file = \(relativeThemePath)\n\(endMarker)"
        let separator = configWithoutManagedBlock.isEmpty || configWithoutManagedBlock.hasSuffix("\n") ? "" : "\n"
        try atomicWrite(configWithoutManagedBlock + separator + managedBlock + "\n", to: configFile)
    }

    private static func removingManagedBlock(from text: String) -> String {
        guard let start = text.range(of: beginMarker),
              let end = text.range(of: endMarker, range: start.lowerBound..<text.endIndex) else {
            return text
        }
        var result = text
        result.removeSubrange(start.lowerBound..<end.upperBound)
        return result.trimmingCharacters(in: .newlines) + (result.contains(where: { !$0.isNewline }) ? "\n" : "")
    }

    private static func atomicWrite(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url, options: .atomic)
    }
}
