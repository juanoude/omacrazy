import Foundation
import Testing
@testable import Omacrazy

@Test func hyprlandRGBAConvertsAlphaAndRGBForJankyBorders() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = try write("col.active_border = rgba(11223380)\n", named: "hyprland.conf", in: root)

    let result = try HyprlandActiveBorder.read(from: file)

    #expect(result.colors == ["0x80112233"])
    #expect(result.jankyBordersValue == "0x80112233")
}

@Test func hyprlandGradientUsesFirstAndLastColors() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = try write(
        "col.active_border = rgba(112233ff) rgba(aabbccdd) 45deg\n",
        named: "hyprland.conf",
        in: root
    )

    let result = try HyprlandActiveBorder.read(from: file)

    #expect(result.jankyBordersValue == "gradient(top_left=0xFF112233,bottom_right=0xDDAABBCC)")
}

@Test func hyprlandParserRejectsMissingOrInvalidActiveBorder() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let missing = try write("general {\n  gaps_in = 4\n}\n", named: "missing.conf", in: root)
    let invalid = try write("col.active_border = not-a-color\n", named: "invalid.conf", in: root)

    #expect(throws: OmacrazyError.self) { try HyprlandActiveBorder.read(from: missing) }
    #expect(throws: OmacrazyError.self) { try HyprlandActiveBorder.read(from: invalid) }
}

@Test func jankyBordersConfigAcceptsHexAndGradientButRejectsShellText() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let single = try write("active_color=0xFF112233\n", named: "single.conf", in: root)
    let gradient = try write(
        "active_color=gradient(top_left=0xFF112233,bottom_right=0xFFAABBCC)\n",
        named: "gradient.conf",
        in: root
    )
    let invalid = try write("active_color=0xFF112233'; touch /tmp/bad\n", named: "invalid-janky.conf", in: root)

    #expect(try JankyBordersThemeConfig.read(from: single) == "0xFF112233")
    #expect(try JankyBordersThemeConfig.read(from: gradient) == "gradient(top_left=0xFF112233,bottom_right=0xFFAABBCC)")
    #expect(throws: OmacrazyError.self) { try JankyBordersThemeConfig.read(from: invalid) }
}

@Test func jankyInferencePrefersHyprlandWhenBothSourcesExist() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try write("col.active_border = rgba(123456ff)\n", named: "hyprland.conf", in: root)
    try write("accent = \"#abcdef\"\nforeground = \"#fedcba\"\n", named: "colors.toml", in: root)

    try ThemeInference.inferJankyBorders(themeName: "sample", themeRoot: root)

    let output = try String(contentsOf: root.appendingPathComponent("jankyborders.conf"), encoding: .utf8)
    #expect(output.contains("# Source: hyprland.conf"))
    #expect(output.contains("active_color=0xFF123456"))
}

@Test func jankyInferenceUsesPaletteAndProducesOneOfThreeChoices() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try write("accent = \"#112233\"\nforeground = \"#aabbcc\"\n", named: "colors.toml", in: root)

    try ThemeInference.inferJankyBorders(themeName: "sample", themeRoot: root)

    let output = try String(contentsOf: root.appendingPathComponent("jankyborders.conf"), encoding: .utf8)
    #expect(output.contains("# Source: colors.toml"))
    let validChoices = [
        "active_color=0xFF112233",
        "active_color=0xFFAABBCC",
        "active_color=gradient(top_left=0xFF112233,bottom_right=0xFFAABBCC)"
    ]
    #expect(validChoices.contains { output.contains($0) }, "unexpected inferred color: \(output)")
}

@Test func jankyInferenceRegeneratesMarkedFileAndPreservesUnmarkedFile() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let hyprland = try write("col.active_border = rgb(112233)\n", named: "hyprland.conf", in: root)
    try ThemeInference.inferJankyBorders(themeName: "sample", themeRoot: root)
    let generated = root.appendingPathComponent("jankyborders.conf")

    try "col.active_border = rgb(aabbcc)\n".write(to: hyprland, atomically: true, encoding: .utf8)
    try ThemeInference.inferJankyBorders(themeName: "sample", themeRoot: root)
    #expect(try String(contentsOf: generated, encoding: .utf8).contains("active_color=0xFFAABBCC"))

    let manualRoot = root.appendingPathComponent("manual", isDirectory: true)
    try FileManager.default.createDirectory(at: manualRoot, withIntermediateDirectories: true)
    let manual = try write("active_color=0xFF010203\n", named: "jankyborders.conf", in: manualRoot)
    try write("col.active_border = rgb(abcdef)\n", named: "hyprland.conf", in: manualRoot)
    try ThemeInference.inferJankyBorders(themeName: "manual", themeRoot: manualRoot)
    #expect(try String(contentsOf: manual, encoding: .utf8) == "active_color=0xFF010203\n")
}

@Test func inferenceDoesNotCreatePartialFileWhenSourceIsInvalid() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try write("col.active_border = invalid\n", named: "hyprland.conf", in: root)

    #expect(throws: OmacrazyError.self) {
        try ThemeInference.inferJankyBorders(themeName: "sample", themeRoot: root)
    }
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("jankyborders.conf").path))
}

@Test func ghosttyGeneratorUsesPaletteAndEmitsSixteenANSIColors() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    var entries = ["background = \"#101010\"", "foreground = \"#eeeeee\""]
    entries += (0..<16).map { "color\($0) = \"#\(String(format: "%06x", $0 + 1))\"" }
    let paletteFile = try write(entries.joined(separator: "\n"), named: "colors.toml", in: root)
    let palette = try ColorPalette.read(from: paletteFile)

    let output = try GhosttyConfigGenerator.generate(from: palette)

    #expect(output.contains(InferredFileWriter.marker))
    #expect(output.contains("background = #101010"))
    #expect(output.contains("foreground = #eeeeee"))
    for index in 0..<16 {
        #expect(output.contains("palette = \(index)=#\(String(format: "%06x", index + 1))"))
    }
}

@Test func zedGeneratorCreatesMarkedDarkThemeFromPalette() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let paletteFile = try write(
        "background = \"#101010\"\nforeground = \"#eeeeee\"\naccent = \"#ff40a3\"\nselection = \"#17294a\"\nred = \"#f02040\"\n",
        named: "colors.toml",
        in: root
    )
    let palette = try ColorPalette.read(from: paletteFile)

    let output = try ZedThemeGenerator.generate(themeName: "my-futurism", palette: palette)
    let data = try #require(output.data(using: .utf8))
    let family = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let theme = try #require((family["themes"] as? [[String: Any]])?.first)
    let style = try #require(theme["style"] as? [String: Any])

    #expect(family["_omacrazy_generated"] as? Bool == true)
    #expect(family["$schema"] as? String == "https://zed.dev/schema/themes/v0.1.0.json")
    #expect(theme["name"] as? String == "My Futurism")
    #expect(theme["appearance"] as? String == "dark")
    #expect(style["editor.background"] as? String == "#101010")
    #expect(style["editor.foreground"] as? String == "#eeeeee")
    #expect(style["terminal.ansi.red"] as? String == "#f02040")
}

@Test func zedInferenceCreatesAndRegeneratesOnlyMarkedThemeFiles() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try write("background = \"#101010\"\nforeground = \"#eeeeee\"\naccent = \"#ff40a3\"\n", named: "colors.toml", in: root)

    try ThemeInference.inferZed(themeName: "sample", themeRoot: root)
    let generated = root.appendingPathComponent("zed.json")
    #expect(try ZedThemeGenerator.isGenerated(at: generated))

    try write("background = \"#202020\"\nforeground = \"#dddddd\"\naccent = \"#aa33ff\"\n", named: "colors.toml", in: root)
    try ThemeInference.inferZed(themeName: "sample", themeRoot: root)
    let updated = try String(contentsOf: generated, encoding: .utf8)
    #expect(updated.contains("#202020"))
    #expect(updated.contains("#aa33ff"))

    let manualRoot = root.appendingPathComponent("manual", isDirectory: true)
    try FileManager.default.createDirectory(at: manualRoot, withIntermediateDirectories: true)
    let manual = try write("{\n  \"name\": \"Custom\"\n}\n", named: "zed.json", in: manualRoot)
    try write("background = \"#303030\"\nforeground = \"#cccccc\"\n", named: "colors.toml", in: manualRoot)
    try ThemeInference.inferZed(themeName: "manual", themeRoot: manualRoot)
    #expect(try String(contentsOf: manual, encoding: .utf8) == "{\n  \"name\": \"Custom\"\n}\n")
}

@Test func zedNumberedPaletteSupportsDistinctSyntaxAndStatusRoles() throws {
    let palette = ColorPalette(values: [
        "background": "#0e091d", "foreground": "#14b9b5", "accent": "#be3f50",
        "cursor": "#ff7f41", "selection_background": "#14b9b5",
        "color1": "#c8e967", "color2": "#e20342", "color3": "#7cd699",
        "color5": "#9147a8", "color7": "#a60234", "color8": "#c53253",
        "color9": "#ce4f48", "color15": "#11aeb3"
    ])
    let output = try ZedThemeGenerator.generate(themeName: "sample", palette: palette)
    let family = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
    let theme = try #require((family["themes"] as? [[String: Any]])?.first)
    let style = try #require(theme["style"] as? [String: Any])
    let syntax = try #require(style["syntax"] as? [String: [String: Any]])

    #expect(syntax["function"]?["color"] as? String == "#be3f50")
    #expect(syntax["keyword"]?["color"] as? String == "#9147a8")
    #expect(syntax["number"]?["color"] as? String == "#ce4f48")
    #expect(syntax["string"]?["color"] as? String == "#e20342")
    #expect(syntax["type"]?["color"] as? String == "#7cd699")
    #expect(syntax["variable"]?["color"] as? String == "#c8e967")
    #expect(syntax["comment"]?["color"] as? String == "#c53253")
    #expect(syntax.count == 31)
    #expect(syntax["comment.doc"]?["font_style"] as? String == "italic")
    #expect(syntax["emphasis"]?["font_style"] as? String == "italic")
    #expect(syntax["emphasis.strong"]?["font_weight"] as? Int == 700)
    #expect(syntax["variable.special"]?["font_style"] as? String == "italic")
    #expect(style["text.muted"] as? String == "#a60234")
    #expect(style["text.accent"] as? String == "#ff7f41")
    #expect(style["error"] as? String == "#c8e967")
    #expect(style["created"] as? String == "#e20342")
    #expect(style["warning"] as? String == "#7cd699")
    #expect(style["modified"] as? String == "#be3f50")
    #expect(style["info"] as? String == "#ff7f41")
    #expect(style["error.background"] as? String == "#0e091d")
    #expect(style["editor.active_line.background"] as? String == "#c5325366")
    #expect(style["editor.highlighted_line.background"] as? String == "#c5325366")
    #expect(style["editor.document_highlight.read_background"] as? String == "#c5325326")
    #expect(style["title_bar.background"] as? String == "#0e091d")
    #expect(style["scrollbar.thumb.background"] as? String == "#c53253")
    for status in ["error", "deleted", "created", "success", "warning", "conflict", "renamed", "unreachable", "modified", "info", "hint", "hidden", "ignored", "predictive"] {
        #expect(style[status] as? String != nil)
        #expect(style["\(status).background"] as? String != nil)
        #expect(style["\(status).border"] as? String != nil)
    }
    let players = try #require(style["players"] as? [[String: String]])
    #expect(players.first?["selection"] == "#c5325366")
    #expect(players.first?["cursor"] == "#ff7f41")
}

@Test func zedSelectionMatchesActiveLineAndPreservesLowerOpacity() throws {
    for (input, expected) in [("#eeeeee", "#eeeeee66"), ("#eeeeee10", "#eeeeee10"), ("#eeeeeeff", "#eeeeee66")] {
        let palette = ColorPalette(values: ["background": "#101010", "foreground": "#eeeeee", "muted": input, "selection_background": "#ff0000"])
        let output = try ZedThemeGenerator.generate(themeName: "sample", palette: palette)
        let family = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        let theme = try #require((family["themes"] as? [[String: Any]])?.first)
        let style = try #require(theme["style"] as? [String: Any])
        let players = try #require(style["players"] as? [[String: String]])
        #expect(players.first?["selection"] == expected)
        #expect(style["search.match_background"] as? String == expected)
        #expect(style["editor.active_line.background"] as? String == expected)
    }
}

@Test func generatedFileWriterRegeneratesMarkedAndPreservesManualFiles() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let generated = try write("\(InferredFileWriter.marker)\nold\n", named: "generated.conf", in: root)
    let manual = try write("custom\n", named: "manual.conf", in: root)

    let generatedResult = try InferredFileWriter.write("\(InferredFileWriter.marker)\nnew\n", to: generated)
    let manualResult = try InferredFileWriter.write("replacement\n", to: manual)

    #expect(generatedResult == .regenerated)
    #expect(try String(contentsOf: generated, encoding: .utf8) == "\(InferredFileWriter.marker)\nnew\n")
    #expect(manualResult == .skipped)
    #expect(try String(contentsOf: manual, encoding: .utf8) == "custom\n")
}

@Test func alacrittyFallbackGeneratesPaletteAndZedWithReferencesAndANSIColors() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    var input = """
    [colors.primary] # primary colors
    background = '#101010'
    foreground = "0xeeeeee" # supported hex prefix
    [colors.cursor]
    cursor = "CellForeground"
    text = "CellBackground"
    [colors.selection]
    background = "CellForeground"
    text = "CellBackground"
    
    """
    let names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
    for (offset, section) in ["normal", "bright"].enumerated() {
        input += "[colors.\(section)]\n"
        for (index, name) in names.enumerated() {
            input += "\(name) = \"\(String(format: "#%06x", offset * 8 + index))\"\n"
        }
    }
    try write(input, named: "alacritty.toml", in: root)
    try ThemeInference.inferZed(themeName: "sample", themeRoot: root)
    let palette = try ColorPalette.read(from: root.appendingPathComponent("colors.toml"))
    #expect(palette.color("background") == "#101010")
    #expect(palette.color("foreground") == "#eeeeee")
    #expect(palette.color("cursor") == "#eeeeee")
    #expect(palette.color("cursor_text") == "#101010")
    #expect(palette.color("selection_background") == "#eeeeee")
    #expect(palette.color("selection_foreground") == "#101010")
    for index in 0..<16 {
        #expect(palette.color("color\(index)") == String(format: "#%06x", index))
    }
    #expect(try ZedThemeGenerator.isGenerated(at: root.appendingPathComponent("zed.json")))
}

@Test func alacrittyFallbackPreservesExistingPaletteAndRejectsInvalidInputWithoutWriting() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(try !AlacrittyPalette.createIfMissing(in: root))
    try write("[colors.primary]\nbackground = \"invalid\"\nforeground = \"#eeeeee\"\n", named: "alacritty.toml", in: root)
    #expect(throws: OmacrazyError.self) { try AlacrittyPalette.createIfMissing(in: root) }
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("colors.toml").path))
    let original = "background = \"#123456\"\nforeground = \"#abcdef\"\n"
    let existing = try write(original, named: "colors.toml", in: root)
    #expect(try !AlacrittyPalette.createIfMissing(in: root))
    #expect(try String(contentsOf: existing, encoding: .utf8) == original)
}

@Test func ghosttyOpacityOverrideLoadsAfterThemesAndPreservesUserConfig() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let configDirectory = root.appendingPathComponent("ghostty")
    let original = "font-size = 14\nbackground-opacity = 0.5\n"
    let config = try write(original, named: "ghostty/config", in: root)
    let lumon = try write("background = #1b2d40\nbackground-opacity = 0.3\n", named: "lumon.conf", in: root)
    let other = try write("background = #101010\n", named: "other.conf", in: root)
    for (name, source) in [("lumon", lumon), ("other", other), ("lumon", lumon)] {
        try GhosttyAdapter.apply(themeName: name, source: source, configDirectory: configDirectory)
        let contents = try String(contentsOf: config, encoding: .utf8)
        #expect(contents.hasPrefix(original))
        #expect(contents.contains("config-file = omacrazy/themes/\(name).conf\nconfig-file = omacrazy/overrides.conf"))
        #expect(contents.components(separatedBy: "# BEGIN OMACRAZY THEME").count == 2)
        let overrides = try String(contentsOf: configDirectory.appendingPathComponent("omacrazy/overrides.conf"), encoding: .utf8)
        #expect(overrides.contains("background-opacity = 0.90"))
    }
    #expect(try String(contentsOf: configDirectory.appendingPathComponent("config.omacrazy-backup"), encoding: .utf8) == original)
    #expect(try String(contentsOf: lumon, encoding: .utf8) == "background = #1b2d40\nbackground-opacity = 0.3\n")
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("omacrazy-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@discardableResult
private func write(_ contents: String, named relativePath: String, in root: URL) throws -> URL {
    let file = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try contents.write(to: file, atomically: true, encoding: .utf8)
    return file
}
