import Foundation

enum AlacrittyPalette {
    /// Create the shared palette once; an existing palette always takes precedence.
    @discardableResult
    static func createIfMissing(in themeRoot: URL) throws -> Bool {
        let destination = themeRoot.appendingPathComponent("colors.toml")
        let source = themeRoot.appendingPathComponent("alacritty.toml")
        guard !FileManager.default.fileExists(atPath: destination.path),
              FileManager.default.fileExists(atPath: source.path) else { return false }
        let palette = try read(from: source)
        let contents = "\(InferredFileWriter.marker)\n# Source: alacritty.toml; edit as needed.\n" +
            palette.values.keys.sorted().map { "\($0) = \"\(palette.values[$0]!)\"\n" }.joined()
        do {
            try Data(contents.utf8).write(to: destination, options: .withoutOverwriting)
        } catch CocoaError.fileWriteFileExists {
            return false
        }
        print("Palette: generated colors.toml from alacritty.toml.")
        return true
    }

    static func read(from file: URL) throws -> ColorPalette {
        let text = try String(contentsOf: file, encoding: .utf8)
        let names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
        var mappings = [
            "colors.primary.background": "background", "colors.primary.foreground": "foreground",
            "colors.primary.dim_foreground": "dark_foreground",
            "colors.primary.bright_foreground": "bright_foreground",
            "colors.cursor.cursor": "cursor", "colors.cursor.text": "cursor_text",
            "colors.selection.background": "selection_background", "colors.selection.text": "selection_foreground"
        ]
        for (index, name) in names.enumerated() {
            mappings["colors.normal.\(name)"] = "color\(index)"
            mappings["colors.bright.\(name)"] = "color\(index + 8)"
        }
        var section = ""
        var rawValues: [String: String] = [:]
        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") {
                section = String(line.prefix { $0 != "]" }.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let path = section.isEmpty ? key : "\(section).\(key)"
            guard let mapped = mappings[path] else { continue }
            let valueText = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard let quote = valueText.first, quote == "\"" || quote == "'",
                  let end = valueText.dropFirst().firstIndex(of: quote),
                  rawValues[mapped] == nil else {
                throw OmacrazyError(description: "invalid or duplicate Alacritty color at line \(index + 1)")
            }
            let trailing = valueText[valueText.index(after: end)...].trimmingCharacters(in: .whitespaces)
            guard trailing.isEmpty || trailing.hasPrefix("#") else {
                throw OmacrazyError(description: "invalid Alacritty color at line \(index + 1)")
            }
            rawValues[mapped] = String(valueText[valueText.index(after: valueText.startIndex)..<end])
        }
        var values: [String: String] = [:]
        for (key, raw) in rawValues {
            let resolved: String
            switch raw {
            case "CellBackground": resolved = rawValues["background"] ?? ""
            case "CellForeground": resolved = rawValues["foreground"] ?? ""
            case "None": continue
            default: resolved = raw
            }
            let color = resolved.hasPrefix("0x") ? "#" + resolved.dropFirst(2) : resolved
            guard ColorPalette(values: [key: color]).color(key) != nil else {
                throw OmacrazyError(description: "invalid Alacritty color '\(raw)' for \(key)")
            }
            values[key] = color
        }
        let palette = ColorPalette(values: values)
        guard palette.color("background") != nil, palette.color("foreground") != nil else {
            throw OmacrazyError(description: "alacritty.toml needs valid colors.primary.background and foreground colors")
        }
        return palette
    }
}
