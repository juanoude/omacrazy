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
        if arguments.first == "theme", arguments.count == 4, arguments[1] == "infer" {
            try ThemeInference.infer(themeName: arguments[2], target: arguments[3])
            return
        }

        if arguments.first == "theme", arguments.count == 4, arguments[1] == "add" {
            try ThemeImporter.add(repository: arguments[2], named: arguments[3])
            return
        }

        guard arguments.first == "theme", arguments.count == 1 || arguments.count == 2 else {
            print("Usage: omacrazy theme [name]\n       omacrazy theme add <repository-url> <name>\n       omacrazy theme infer <name> <target>")
            if !arguments.isEmpty { throw OmacrazyError(description: "unsupported command") }
            return
        }

        let themeName: String
        if arguments.count == 1 {
            let themes = try ThemePicker.availableThemes(in: ThemeLocator.themesDirectory())
            guard let selected = try ThemePicker.choose(from: themes) else {
                print("Theme selection cancelled.")
                return
            }
            themeName = selected
        } else {
            themeName = arguments[1]
        }
        guard themeName.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil else {
            throw OmacrazyError(description: "invalid theme name '\(themeName)'")
        }

        let themeRoot = try ThemeLocator.findTheme(named: themeName)
        var succeeded = 0
        var failed = 0

        do {
            try AlacrittyPalette.createIfMissing(in: themeRoot)
        } catch {
            fputs("Palette: generation failed: \(error)\n", stderr)
            failed += 1
        }

        let ghosttySource = themeRoot.appendingPathComponent("ghostty.conf")
        var ghosttyInferenceFailed = false
        if !FileManager.default.fileExists(atPath: ghosttySource.path),
           FileManager.default.fileExists(atPath: themeRoot.appendingPathComponent("colors.toml").path) {
            do {
                try ThemeInference.infer(themeName: themeName, target: "ghostty")
            } catch {
                fputs("Ghostty: inference failed: \(error)\n", stderr)
                failed += 1
                ghosttyInferenceFailed = true
            }
        }
        if FileManager.default.fileExists(atPath: ghosttySource.path) {
            do {
                try GhosttyAdapter.apply(themeName: themeName, source: ghosttySource)
                print("Ghostty: applied '\(themeName)' (reload with Cmd+Shift+Comma).")
                succeeded += 1
            } catch {
                fputs("Ghostty: failed: \(error)\n", stderr)
                failed += 1
            }
        } else if !ghosttyInferenceFailed {
            print("Ghostty: skipped (theme has no ghostty.conf).")
        }

        let bordersThemeSource = themeRoot.appendingPathComponent("jankyborders.conf")
        let hasJankyBordersSource = FileManager.default.fileExists(atPath: themeRoot.appendingPathComponent("hyprland.conf").path) ||
            FileManager.default.fileExists(atPath: themeRoot.appendingPathComponent("colors.toml").path)
        var jankyBordersInferenceFailed = false
        if hasJankyBordersSource {
            do {
                let shouldInfer: Bool
                if FileManager.default.fileExists(atPath: bordersThemeSource.path) {
                    shouldInfer = try ThemeInference.isGeneratedJankyBordersConfig(at: bordersThemeSource)
                } else {
                    shouldInfer = true
                }
                if shouldInfer {
                    try ThemeInference.infer(themeName: themeName, target: "jankyborders")
                }
            } catch {
                fputs("JankyBorders: inference failed: \(error)\n", stderr)
                failed += 1
                jankyBordersInferenceFailed = true
            }
        }
        if FileManager.default.fileExists(atPath: bordersThemeSource.path) {
            if !jankyBordersInferenceFailed {
                do {
                    let activeColor = try JankyBordersThemeConfig.read(from: bordersThemeSource)
                    let result = try JankyBordersAdapter.apply(activeColor: activeColor)
                    print("JankyBorders: \(result)")
                    succeeded += 1
                } catch {
                    fputs("JankyBorders: failed: \(error)\n", stderr)
                    failed += 1
                }
            }
        } else {
            if !jankyBordersInferenceFailed {
                print("JankyBorders: skipped (theme has no jankyborders.conf; run 'omacrazy theme infer \(themeName) jankyborders').")
            }
        }

        do {
            if try !ZedAdapter.hasTheme(themeRoot: themeRoot),
               FileManager.default.fileExists(atPath: themeRoot.appendingPathComponent("colors.toml").path) {
                try ThemeInference.infer(themeName: themeName, target: "zed")
            }
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

enum ThemeInference {
    static func isGeneratedJankyBordersConfig(at file: URL) throws -> Bool {
        try InferredFileWriter.isGenerated(at: file, legacyMarkers: jankyBordersLegacyMarkers)
    }

    private static let jankyBordersLegacyMarkers = [
        "# Generated from hyprland.conf by omacrazy; edit as needed.",
        "# Generated from colors.toml by omacrazy; edit as needed."
    ]
    private static let ghosttyLegacyMarkers = ["# Generated from colors.toml by omacrazy; edit as needed."]

    static func infer(themeName: String, target: String) throws {
        guard themeName.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil else {
            throw OmacrazyError(description: "invalid theme name '\(themeName)'")
        }
        guard target == "ghostty" || target == "jankyborders" || target == "zed" || target == "colors" else {
            throw OmacrazyError(description: "unsupported inference target '\(target)' (supported: ghostty, jankyborders, zed, colors)")
        }

        let themeRoot = try ThemeLocator.findTheme(named: themeName)
        if target == "colors" {
            if !FileManager.default.fileExists(atPath: themeRoot.appendingPathComponent("colors.toml").path),
               !FileManager.default.fileExists(atPath: themeRoot.appendingPathComponent("alacritty.toml").path) {
                throw OmacrazyError(description: "theme '\(themeName)' has no alacritty.toml to generate colors.toml")
            }
            if try !AlacrittyPalette.createIfMissing(in: themeRoot) {
                print("Palette: skipped (colors.toml already exists; left unchanged).")
            }
            return
        }
        if target == "jankyborders" {
            try inferJankyBorders(themeName: themeName, themeRoot: themeRoot)
            return
        }
        if target == "zed" {
            try inferZed(themeName: themeName, themeRoot: themeRoot)
            return
        }

        let destination = themeRoot.appendingPathComponent("ghostty.conf")
        if FileManager.default.fileExists(atPath: destination.path),
           try !InferredFileWriter.isGenerated(at: destination, legacyMarkers: ghosttyLegacyMarkers) {
            print("Ghostty: skipped inference (\(destination.lastPathComponent) already exists; left unchanged).")
            return
        }

        let paletteFile = themeRoot.appendingPathComponent("colors.toml")
        try AlacrittyPalette.createIfMissing(in: themeRoot)
        guard FileManager.default.fileExists(atPath: paletteFile.path) else {
            throw OmacrazyError(description: "theme '\(themeName)' has no colors.toml palette")
        }
        let palette = try ColorPalette.read(from: paletteFile)
        let output = try GhosttyConfigGenerator.generate(from: palette)
        switch try InferredFileWriter.write(output, to: destination, legacyMarkers: ghosttyLegacyMarkers) {
        case .created:
            print("Ghostty: generated \(destination.lastPathComponent) from colors.toml; review it before applying the theme.")
        case .regenerated:
            print("Ghostty: regenerated \(destination.lastPathComponent) from colors.toml.")
        case .skipped:
            print("Ghostty: skipped inference (\(destination.lastPathComponent) already exists and is not infer-generated; left unchanged).")
        }
    }

    static func inferJankyBorders(themeName: String, themeRoot: URL) throws {
        let destination = themeRoot.appendingPathComponent("jankyborders.conf")
        if FileManager.default.fileExists(atPath: destination.path),
           try !InferredFileWriter.isGenerated(at: destination, legacyMarkers: jankyBordersLegacyMarkers) {
            print("JankyBorders: skipped inference (\(destination.lastPathComponent) already exists; left unchanged).")
            return
        }

        let hyprlandSource = themeRoot.appendingPathComponent("hyprland.conf")
        let activeColor: String
        let sourceDescription: String
        if FileManager.default.fileExists(atPath: hyprlandSource.path) {
            let colors = try HyprlandActiveBorder.read(from: hyprlandSource)
            activeColor = colors.jankyBordersValue
            sourceDescription = "hyprland.conf"
        } else {
            try AlacrittyPalette.createIfMissing(in: themeRoot)
            let paletteSource = themeRoot.appendingPathComponent("colors.toml")
            guard FileManager.default.fileExists(atPath: paletteSource.path) else {
                throw OmacrazyError(description: "theme '\(themeName)' has neither hyprland.conf nor colors.toml for JankyBorders inference")
            }
            let palette = try ColorPalette.read(from: paletteSource)
            let accent = palette.color("accent").map(Self.jankyColor(fromPaletteColor:))
            let foreground = palette.color("foreground").map(Self.jankyColor(fromPaletteColor:))
            guard accent != nil || foreground != nil else {
                throw OmacrazyError(description: "colors.toml needs a valid accent or foreground color for JankyBorders inference")
            }
            switch (accent, foreground) {
            case let (accent?, foreground?):
                switch Int.random(in: 0..<3) {
                case 0: activeColor = accent
                case 1: activeColor = foreground
                default: activeColor = "gradient(top_left=\(accent),bottom_right=\(foreground))"
                }
            case let (accent?, nil):
                activeColor = accent
            case let (nil, foreground?):
                activeColor = foreground
            case (nil, nil):
                throw OmacrazyError(description: "colors.toml needs a valid accent or foreground color for JankyBorders inference")
            }
            sourceDescription = "colors.toml"
        }

        let contents = "\(InferredFileWriter.marker)\n# Source: \(sourceDescription); edit as needed.\nactive_color=\(activeColor)\n"
        switch try InferredFileWriter.write(contents, to: destination, legacyMarkers: jankyBordersLegacyMarkers) {
        case .created:
            print("JankyBorders: generated \(destination.lastPathComponent) from \(sourceDescription); review it before applying the theme.")
        case .regenerated:
            print("JankyBorders: regenerated \(destination.lastPathComponent) from \(sourceDescription).")
        case .skipped:
            print("JankyBorders: skipped inference (\(destination.lastPathComponent) already exists and is not infer-generated; left unchanged).")
        }
    }

    static func inferZed(themeName: String, themeRoot: URL) throws {
        let destination = themeRoot.appendingPathComponent("zed.json")
        if !FileManager.default.fileExists(atPath: destination.path),
           try ZedAdapter.hasTheme(themeRoot: themeRoot) {
            print("Zed: skipped inference (theme already contains a Zed theme).")
            return
        }
        if FileManager.default.fileExists(atPath: destination.path),
           try !ZedThemeGenerator.isGenerated(at: destination) {
            print("Zed: skipped inference (zed.json already exists and is not infer-generated; left unchanged).")
            return
        }

        try AlacrittyPalette.createIfMissing(in: themeRoot)
        let paletteSource = themeRoot.appendingPathComponent("colors.toml")
        guard FileManager.default.fileExists(atPath: paletteSource.path) else {
            throw OmacrazyError(description: "theme '\(themeName)' has no colors.toml palette for Zed inference")
        }
        let palette = try ColorPalette.read(from: paletteSource)
        let output = try ZedThemeGenerator.generate(themeName: themeName, palette: palette)
        switch try ZedThemeGenerator.write(output, to: destination) {
        case .created:
            print("Zed: generated zed.json from colors.toml; review it before applying the theme.")
        case .regenerated:
            print("Zed: regenerated zed.json from colors.toml.")
        case .skipped:
            print("Zed: skipped inference (zed.json already exists and is not infer-generated; left unchanged).")
        }
    }

    private static func jankyColor(fromPaletteColor color: String) -> String {
        let hex = String(color.dropFirst()).uppercased()
        if hex.count == 8 {
            return "0x\(hex.suffix(2))\(hex.prefix(6))"
        }
        return "0xFF\(hex)"
    }
}

enum JankyBordersThemeConfig {
    static func read(from file: URL) throws -> String {
        let contents: String
        do {
            contents = try String(contentsOf: file, encoding: .utf8)
        } catch {
            throw OmacrazyError(description: "could not read jankyborders.conf: \(error)")
        }

        let value = contents.components(separatedBy: .newlines).compactMap { rawLine -> String? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { return nil }
            guard let separator = line.firstIndex(of: "=") else { return nil }
            guard line[..<separator].trimmingCharacters(in: .whitespaces) == "active_color" else { return nil }
            return line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        }.last

        guard let value,
              value.range(of: #"^(?:0x[0-9A-Fa-f]{8}|gradient\(top_left=0x[0-9A-Fa-f]{8},bottom_right=0x[0-9A-Fa-f]{8}\))$"#, options: .regularExpression) != nil else {
            throw OmacrazyError(description: "jankyborders.conf has no valid active_color setting")
        }
        return value
    }
}

enum InferredFileWriter {
    static let marker = "# Generated by omacrazy theme infer"

    enum Outcome: Equatable {
        case created
        case regenerated
        case skipped
    }

    static func isGenerated(at file: URL, legacyMarkers: [String] = []) throws -> Bool {
        let contents = try String(contentsOf: file, encoding: .utf8)
        let firstLine = contents.components(separatedBy: .newlines).first ?? ""
        return firstLine == marker || legacyMarkers.contains(firstLine)
    }

    static func write(_ contents: String, to file: URL, legacyMarkers: [String] = []) throws -> Outcome {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: file.path) {
            guard try isGenerated(at: file, legacyMarkers: legacyMarkers) else { return .skipped }
            try Data(contents.utf8).write(to: file, options: .atomic)
            return .regenerated
        }

        do {
            try Data(contents.utf8).write(to: file, options: .withoutOverwriting)
            return .created
        } catch CocoaError.fileWriteFileExists {
            guard try isGenerated(at: file, legacyMarkers: legacyMarkers) else { return .skipped }
            try Data(contents.utf8).write(to: file, options: .atomic)
            return .regenerated
        }
    }
}

struct ColorPalette {
    let values: [String: String]

    func color(_ key: String) -> String? {
        guard let value = values[key], value.range(of: #"^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    static func read(from url: URL) throws -> ColorPalette {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw OmacrazyError(description: "could not read colors.toml: \(error)")
        }

        var values: [String: String] = [:]
        for (lineNumber, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let separator = line.firstIndex(of: "=") else {
                throw OmacrazyError(description: "invalid colors.toml at line \(lineNumber + 1): expected key = value")
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let rawValue = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard key.range(of: #"^[a-zA-Z][a-zA-Z0-9_-]*$"#, options: .regularExpression) != nil,
                  !rawValue.isEmpty else {
                throw OmacrazyError(description: "invalid colors.toml at line \(lineNumber + 1)")
            }
            let value: String
            if rawValue.first == "\"" || rawValue.first == "'" {
                guard rawValue.count >= 2, rawValue.last == rawValue.first else {
                    throw OmacrazyError(description: "invalid colors.toml string at line \(lineNumber + 1)")
                }
                value = String(rawValue.dropFirst().dropLast())
            } else if rawValue.range(of: #"^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#, options: .regularExpression) != nil {
                // Accept bare hex colors as found in some existing theme palettes.
                value = rawValue
            } else {
                value = String(rawValue.prefix { $0 != "#" }).trimmingCharacters(in: .whitespaces)
            }
            guard values[key] == nil else {
                throw OmacrazyError(description: "duplicate colors.toml key '\(key)'")
            }
            values[key] = value
        }
        return ColorPalette(values: values)
    }
}

enum GhosttyConfigGenerator {
    static func generate(from palette: ColorPalette) throws -> String {
        guard let background = palette.color("background") else {
            throw OmacrazyError(description: "colors.toml is missing a valid background color")
        }
        guard let foreground = palette.color("foreground") else {
            throw OmacrazyError(description: "colors.toml is missing a valid foreground color")
        }

        let cursor = palette.color("cursor") ?? palette.color("accent") ?? foreground
        let cursorText = palette.color("cursor_text") ?? background
        let selectionBackground = palette.color("selection_background") ?? palette.color("selection") ?? background
        let selectionForeground = palette.color("selection_foreground") ?? foreground
        var lines = [
            InferredFileWriter.marker,
            "# Source: colors.toml; edit as needed.",
            "background = \(background)",
            "foreground = \(foreground)",
            "cursor-color = \(cursor)",
            "cursor-text = \(cursorText)",
            "selection-background = \(selectionBackground)",
            "selection-foreground = \(selectionForeground)",
            ""
        ]

        let standard = ansiColors(prefix: "", palette: palette, foreground: foreground, background: background)
        let bright = ansiColors(prefix: "bright_", palette: palette, foreground: foreground, background: background)
        lines.append("# normal colors")
        for index in 0..<8 { lines.append("palette = \(index)=\(standard[index])") }
        lines.append("")
        lines.append("# bright colors")
        for index in 0..<8 { lines.append("palette = \(index + 8)=\(bright[index])") }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func ansiColors(prefix: String, palette: ColorPalette, foreground: String, background: String) -> [String] {
        let names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
        let fallbackKeys = prefix.isEmpty
            ? ["darker_background", "red", "green", "yellow", "blue", "magenta", "cyan", "light_foreground"]
            : ["muted", "bright_red", "bright_green", "bright_yellow", "bright_blue", "bright_magenta", "bright_cyan", "bright_foreground"]
        return names.enumerated().map { index, name in
            let numberedKey = "color\(index + (prefix.isEmpty ? 0 : 8))"
            if let color = palette.color(numberedKey) { return color }
            if let color = palette.color(prefix + name) { return color }
            if let color = palette.color(fallbackKeys[index]) { return color }
            return index == 0 ? background : foreground
        }
    }
}

enum ThemeImporter {
    static func add(repository: String, named name: String) throws {
        guard name.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil else {
            throw OmacrazyError(description: "invalid theme name '\(name)'")
        }
        guard let repoURL = URL(string: repository),
              repoURL.scheme == "https",
              repoURL.host?.lowercased() == "github.com" else {
            throw OmacrazyError(description: "repository must be an https://github.com/... URL")
        }

        let themeDirectory = try ThemeLocator.themesDirectory()
        let destination = themeDirectory.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw OmacrazyError(description: "theme '\(name)' already exists at \(destination.path)")
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omacrazy-theme-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let checkout = temporaryDirectory.appendingPathComponent("checkout", isDirectory: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "clone", "--depth", "1", "--", repository, checkout.path]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw OmacrazyError(description: "could not clone theme repository\(message?.isEmpty == false ? ": \(message!)" : "")")
        }

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        do {
            try copyThemeContents(from: checkout, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        print("Added theme '\(name)' to \(destination.path).")
    }

    private static func copyThemeContents(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        for item in try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let leaf = item.lastPathComponent
            if leaf == ".git" || leaf == ".gitignore" || leaf == ".gitattributes" || leaf == ".gitmodules" { continue }
            let target = destination.appendingPathComponent(leaf)
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                let link = try manager.destinationOfSymbolicLink(atPath: item.path)
                try manager.createSymbolicLink(atPath: target.path, withDestinationPath: link)
            } else if values.isDirectory == true {
                try manager.createDirectory(at: target, withIntermediateDirectories: false)
                try copyThemeContents(from: item, to: target)
            } else {
                try manager.copyItem(at: item, to: target)
            }
        }
    }
}

enum ThemeLocator {
    static var installedThemesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/omacrazy/themes", isDirectory: true)
    }

    static func themesDirectory(
        installedDirectory: URL = installedThemesDirectory,
        searchStarts: [URL] = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
            URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
        ]
    ) throws -> URL {
        let fileManager = FileManager.default
        func isDirectory(_ url: URL) -> Bool {
            var directory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
        }
        if isDirectory(installedDirectory) { return installedDirectory }

        // Allow development from a checkout before the first installation.
        for start in searchStarts {
            var directory = start
            while true {
                let candidate = directory.appendingPathComponent("themes", isDirectory: true)
                if isDirectory(candidate) { return candidate }
                let parent = directory.deletingLastPathComponent()
                if parent.path == directory.path { break }
                directory = parent
            }
        }
        throw OmacrazyError(description: "could not find themes at \(installedDirectory.path); run ./install.sh from the project")
    }

    static func findTheme(named name: String) throws -> URL {
        let directory = try themesDirectory()
        let candidate = directory.appendingPathComponent(name, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw OmacrazyError(description: "theme '\(name)' not found in \(directory.path)")
        }
        return candidate
    }
}

enum GhosttyAdapter {
    private static let beginMarker = "# BEGIN OMACRAZY THEME"
    private static let endMarker = "# END OMACRAZY THEME"

    static func apply(themeName: String, source: URL, configDirectory overrideDirectory: URL? = nil) throws {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let configDirectory: URL
        if let overrideDirectory {
            configDirectory = overrideDirectory
        } else if let override = ProcessInfo.processInfo.environment["OMACRAZY_GHOSTTY_CONFIG_DIR"], !override.isEmpty {
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
        let overridesFile = configDirectory.appendingPathComponent("omacrazy/overrides.conf")
        try atomicWrite("# Managed by Omacrazy: keep terminal opacity independent of the theme.\nbackground-opacity = 0.90\n", to: overridesFile)

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
        // Ghostty processes includes after their parent file, in order. Load
        // personal overrides last so theme-provided opacity cannot take precedence.
        let managedBlock = "\(beginMarker)\nconfig-file = \(relativeThemePath)\nconfig-file = omacrazy/overrides.conf\n\(endMarker)"
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
