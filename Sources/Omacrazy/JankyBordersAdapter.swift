import Foundation

struct HyprlandBorderColors {
    let colors: [String]

    var jankyBordersValue: String {
        let first = colors[0]
        guard colors.count > 1 else { return first }
        let last = colors[colors.count - 1]
        return "gradient(top_left=\(first),bottom_right=\(last))"
    }
}

enum HyprlandActiveBorder {
    static func read(from file: URL) throws -> HyprlandBorderColors {
        let contents = try String(contentsOf: file, encoding: .utf8)
        let assignment = contents
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let uncommented = line.components(separatedBy: "#").first ?? line
                let parts = uncommented.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespaces) == "col.active_border" else { return nil }
                return String(parts[1])
            }
            .last

        guard let assignment else {
            throw OmacrazyError(description: "hyprland.conf has no col.active_border setting")
        }

        let pattern = #"(?:rgba?)\(\s*([0-9a-fA-F]{6}|[0-9a-fA-F]{8})\s*\)|\b0x([0-9a-fA-F]{6}|[0-9a-fA-F]{8})\b"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(assignment.startIndex..<assignment.endIndex, in: assignment)
        var colors: [String] = []
        for match in regex.matches(in: assignment, range: range) {
            let capturedRange = (1..<match.numberOfRanges)
                .compactMap { match.range(at: $0).location == NSNotFound ? nil : match.range(at: $0) }
                .first
            guard let capturedRange, let swiftRange = Range(capturedRange, in: assignment) else { continue }
            colors.append(jankyColor(from: String(assignment[swiftRange])))
        }

        guard !colors.isEmpty else {
            throw OmacrazyError(description: "could not read an RGB color from col.active_border")
        }
        return HyprlandBorderColors(colors: colors)
    }

    private static func jankyColor(from hyprlandHex: String) -> String {
        let value = hyprlandHex.uppercased()
        if value.count == 8 {
            // Hyprland rgba() stores RRGGBBAA; JankyBorders expects AARRGGBB.
            return "0x\(value.suffix(2))\(value.prefix(6))"
        }
        return "0xFF\(value)"
    }
}

enum JankyBordersAdapter {
    private static let beginMarker = "# BEGIN OMACRAZY THEME"
    private static let endMarker = "# END OMACRAZY THEME"

    static func apply(colors: HyprlandBorderColors) throws -> String {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let configFile: URL
        if let override = ProcessInfo.processInfo.environment["OMACRAZY_BORDERS_CONFIG"], !override.isEmpty {
            configFile = URL(fileURLWithPath: override)
        } else {
            configFile = home.appendingPathComponent(".config/borders/bordersrc")
        }

        try fileManager.createDirectory(
            at: configFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let existing = fileManager.fileExists(atPath: configFile.path)
        let original = existing ? try String(contentsOf: configFile, encoding: .utf8) : "#!/bin/bash\n"
        if existing {
            let backup = configFile.deletingLastPathComponent()
                .appendingPathComponent(configFile.lastPathComponent + ".omacrazy-backup")
            if !fileManager.fileExists(atPath: backup.path) {
                try fileManager.copyItem(at: configFile, to: backup)
            }
        }

        let withoutManagedBlock = removingManagedBlock(from: original)
        let command = "borders 'active_color=\(colors.jankyBordersValue)'"
        let block = "\(beginMarker)\n\(command)\n\(endMarker)"
        let separator = withoutManagedBlock.isEmpty || withoutManagedBlock.hasSuffix("\n") ? "" : "\n"
        try atomicWrite(withoutManagedBlock + separator + block + "\n", to: configFile, isNewScript: !existing)

        guard isRunning() else {
            return "saved active border color for the next JankyBorders launch (not currently running)"
        }
        guard let executable = executableURL(named: "borders") else {
            return "saved active border color, but could not find the borders command on PATH to update the running process"
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["active_color=\(colors.jankyBordersValue)"]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: detail, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw OmacrazyError(description: message.flatMap { $0.isEmpty ? nil : $0 } ?? "borders exited with status \(process.terminationStatus)")
        }
        return "updated the running process and saved the color for future launches"
    }

    private static func isRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "borders"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func executableURL(named name: String) -> URL? {
        let paths = ProcessInfo.processInfo.environment["PATH", default: ""].split(separator: ":")
        return paths
            .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
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

    private static func atomicWrite(_ contents: String, to url: URL, isNewScript: Bool) throws {
        try Data(contents.utf8).write(to: url, options: .atomic)
        if isNewScript {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }
}
