import Foundation

enum ZedThemeGenerator {
    private static let generatedMarker = "_omacrazy_generated"

    enum WriteOutcome: Equatable {
        case created
        case regenerated
        case skipped
    }

    static func generate(themeName: String, palette: ColorPalette) throws -> String {
        guard let background = palette.color("background") else {
            throw OmacrazyError(description: "colors.toml is missing a valid background color")
        }
        guard let foreground = palette.color("foreground") else {
            throw OmacrazyError(description: "colors.toml is missing a valid foreground color")
        }

        // Resolve semantic roles from either named or numbered ANSI palettes.
        func role(_ name: String, slot: Int, fallback: String) -> String {
            palette.color(name) ?? palette.color("color\(slot)") ?? fallback
        }
        let accent = palette.color("accent") ?? role("blue", slot: 4, fallback: foreground)
        let red = role("red", slot: 1, fallback: accent)
        let green = role("green", slot: 2, fallback: accent)
        let yellow = role("yellow", slot: 3, fallback: accent)
        let magenta = role("magenta", slot: 5, fallback: accent)
        let cyan = role("cyan", slot: 6, fallback: accent)
        let brightRed = role("bright_red", slot: 9, fallback: red)
        let muted = palette.color("muted") ?? palette.color("dark_foreground") ?? role("bright_black", slot: 8, fallback: foreground)
        let subduedText = palette.color("muted") ?? palette.color("dark_foreground") ?? role("white", slot: 7, fallback: muted)
        let brightForeground = palette.color("bright_foreground") ?? role("bright_white", slot: 15, fallback: foreground)
        let cursor = palette.color("cursor") ?? cyan
        let activeLine = translucent(muted, maximumAlpha: 0x66)
        let selection = activeLine
        let documentHighlight = translucent(muted, maximumAlpha: 0x26)
        let darkBackground = palette.color("dark_background") ?? palette.color("darker_background") ?? background
        let raisedBackground = palette.color("lighter_background") ?? palette.color("selection") ?? background
        let ansi = ansiColors(from: palette, background: background, foreground: foreground)

        var style: [String: Any] = [
            "background": background,
            "border": darkBackground,
            "border.disabled": darkBackground,
            "border.focused": accent,
            "border.selected": accent,
            "border.variant": darkBackground,
            "editor.active_line.background": activeLine,
            "editor.active_line_number": brightForeground,
            "editor.background": background,
            "editor.foreground": foreground,
            "editor.gutter.background": background,
            "editor.highlighted_line.background": activeLine,
            "editor.line_number": muted,
            "editor.subheader.background": darkBackground,
            "editor.wrap_guide": activeLine,
            "editor.active_wrap_guide": documentHighlight,
            "editor.document_highlight.read_background": documentHighlight,
            "editor.document_highlight.write_background": documentHighlight,
            "drop_target.background": selection,
            "element.active": selection,
            "element.background": raisedBackground,
            "element.hover": selection,
            "element.selected": selection,
            "elevated_surface.background": raisedBackground,
            "ghost_element.active": selection,
            "ghost_element.background": background,
            "ghost_element.hover": selection,
            "ghost_element.selected": selection,
            "icon": foreground,
            "icon.accent": accent,
            "icon.disabled": subduedText,
            "icon.muted": subduedText,
            "icon.placeholder": subduedText,
            "panel.background": darkBackground,
            "panel.focused_border": accent,
            "pane.focused_border": accent,
            "players": [["cursor": cursor, "background": background, "selection": selection]],
            "scrollbar.thumb.background": muted,
            "scrollbar.thumb.hover_background": subduedText,
            "scrollbar.thumb.border": translucent(background, maximumAlpha: 0x6F),
            "scrollbar.track.border": darkBackground,
            "scrollbar.track.background": darkBackground,
            "status_bar.background": darkBackground,
            "surface.background": darkBackground,
            "tab.active_background": background,
            "tab.inactive_background": darkBackground,
            "tab_bar.background": darkBackground,
            "title_bar.background": darkBackground,
            "title_bar.inactive_background": raisedBackground,
            "toolbar.background": darkBackground,
            "search.match_background": selection,
            "link_text.hover": cursor,
            "text": foreground,
            "text.accent": cursor,
            "text.disabled": subduedText,
            "text.muted": subduedText,
            "text.placeholder": subduedText,
            "terminal.background": background,
            "terminal.foreground": foreground,
            "terminal.dim_foreground": muted,
            "terminal.bright_foreground": brightForeground,
            "terminal.ansi.black": ansi[0],
            "terminal.ansi.red": ansi[1],
            "terminal.ansi.green": ansi[2],
            "terminal.ansi.yellow": ansi[3],
            "terminal.ansi.blue": ansi[4],
            "terminal.ansi.magenta": ansi[5],
            "terminal.ansi.cyan": ansi[6],
            "terminal.ansi.white": ansi[7],
            "terminal.ansi.bright_black": ansi[8],
            "terminal.ansi.bright_red": ansi[9],
            "terminal.ansi.bright_green": ansi[10],
            "terminal.ansi.bright_yellow": ansi[11],
            "terminal.ansi.bright_blue": ansi[12],
            "terminal.ansi.bright_magenta": ansi[13],
            "terminal.ansi.bright_cyan": ansi[14],
            "terminal.ansi.bright_white": ansi[15],
            "syntax": [
                "attribute": ["color": accent],
                "boolean": ["color": brightRed],
                "comment": ["color": muted, "font_style": "italic"],
                "comment.doc": ["color": muted, "font_style": "italic"],
                "constant": ["color": brightRed],
                "constructor": ["color": red],
                "emphasis": ["color": red, "font_style": "italic"],
                "emphasis.strong": ["color": red, "font_weight": 700],
                "function": ["color": accent],
                "keyword": ["color": magenta],
                "label": ["color": yellow],
                "link_text": ["color": red],
                "link_uri": ["color": red],
                "number": ["color": brightRed],
                "operator": ["color": accent],
                "punctuation": ["color": foreground],
                "punctuation.bracket": ["color": foreground],
                "punctuation.delimiter": ["color": foreground],
                "punctuation.list_marker": ["color": foreground],
                "punctuation.special": ["color": foreground],
                "string": ["color": green],
                "string.escape": ["color": brightRed],
                "string.regex": ["color": green],
                "string.special": ["color": green],
                "string.special.symbol": ["color": green],
                "tag": ["color": red],
                "text.literal": ["color": green],
                "title": ["color": yellow],
                "type": ["color": yellow],
                "variable": ["color": red],
                "variable.special": ["color": red, "font_style": "italic"]
            ]
        ]

        let statusColors = [
            "error": red, "deleted": red,
            "created": green, "success": green,
            "warning": yellow, "conflict": yellow, "renamed": yellow, "unreachable": yellow,
            "modified": accent, "info": cursor, "hint": foreground,
            "hidden": muted, "ignored": muted, "predictive": muted
        ]
        for (status, color) in statusColors {
            style[status] = color
            style["\(status).background"] = background
            style["\(status).border"] = color
        }
        style["hint.border"] = cursor
        style["predictive.background"] = activeLine

        // Include a discoverable marker so infer can safely refresh only its own output.
        let family: [String: Any] = [
            "$schema": "https://zed.dev/schema/themes/v0.1.0.json",
            "_omacrazy_generated": true,
            "author": "Omacrazy",
            "name": displayName(for: themeName),
            "themes": [[
                "name": displayName(for: themeName),
                "appearance": "dark",
                "style": style
            ]]
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: family, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            return String(decoding: data, as: UTF8.self) + "\n"
        } catch {
            throw OmacrazyError(description: "could not generate Zed theme JSON: \(error)")
        }
    }

    /// Cap highlight opacity while preserving any lower alpha supplied by the theme.
    private static func translucent(_ color: String, maximumAlpha: UInt8) -> String {
        let hex = String(color.dropFirst())
        let suppliedAlpha = hex.count == 8 ? UInt8(hex.suffix(2), radix: 16) ?? 255 : 255
        return "#" + hex.prefix(6) + String(format: "%02x", min(suppliedAlpha, maximumAlpha))
    }

    static func isGenerated(at file: URL) throws -> Bool {
        let data = try Data(contentsOf: file)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return root[generatedMarker] as? Bool == true
    }

    static func write(_ contents: String, to file: URL) throws -> WriteOutcome {
        if FileManager.default.fileExists(atPath: file.path) {
            guard try isGenerated(at: file) else { return .skipped }
            try Data(contents.utf8).write(to: file, options: .atomic)
            return .regenerated
        }
        do {
            try Data(contents.utf8).write(to: file, options: .withoutOverwriting)
            return .created
        } catch CocoaError.fileWriteFileExists {
            guard try isGenerated(at: file) else { return .skipped }
            try Data(contents.utf8).write(to: file, options: .atomic)
            return .regenerated
        }
    }

    private static func ansiColors(from palette: ColorPalette, background: String, foreground: String) -> [String] {
        let names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
        let fallback = [
            "darker_background", "red", "green", "yellow", "blue", "magenta", "cyan", "light_foreground",
            "muted", "bright_red", "bright_green", "bright_yellow", "bright_blue", "bright_magenta", "bright_cyan", "bright_foreground"
        ]
        return (0..<16).map { index in
            if let numbered = palette.color("color\(index)") { return numbered }
            let semanticKey = (index < 8 ? "" : "bright_") + names[index % 8]
            if let semantic = palette.color(semanticKey) { return semantic }
            if let fallbackColor = palette.color(fallback[index]) { return fallbackColor }
            return index == 0 ? background : foreground
        }
    }

    private static func displayName(for themeName: String) -> String {
        themeName.split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { word in word.prefix(1).uppercased() + word.dropFirst() }
            .joined(separator: " ")
    }
}
