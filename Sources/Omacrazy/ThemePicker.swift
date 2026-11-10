import Darwin
import Foundation

enum ThemePicker {
    static func availableThemes(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ).filter {
            guard $0.lastPathComponent.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil else { return false }
            return try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        }.map(\.lastPathComponent).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func choose(from themes: [String]) throws -> String? {
        guard !themes.isEmpty else {
            throw OmacrazyError(description: "no themes found in themes/")
        }
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
            throw OmacrazyError(description: "the theme picker requires an interactive terminal; use 'omacrazy theme <name>'")
        }
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            throw OmacrazyError(description: "could not read terminal settings")
        }
        var raw = original
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO | ISIG | IEXTEN)
        raw.c_iflag &= ~tcflag_t(IXON)
        withUnsafeMutableBytes(of: &raw.c_cc) { controls in
            controls[Int(VMIN)] = 1
            controls[Int(VTIME)] = 0
        }
        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else {
            throw OmacrazyError(description: "could not configure the terminal picker")
        }
        let visibleCount = min(themes.count, 10)
        var selected = 0
        var drawn = false
        func output(_ text: String) { FileHandle.standardOutput.write(Data(text.utf8)) }
        func clear() {
            guard drawn else { return }
            output("\u{1B}[\(visibleCount + 1)A")
            for _ in 0...visibleCount { output("\r\u{1B}[2K\n") }
            output("\u{1B}[\(visibleCount + 1)A\r")
        }
        defer {
            clear()
            output("\u{1B}[?25h")
            tcsetattr(STDIN_FILENO, TCSANOW, &original)
        }
        output("\u{1B}[?25l")
        while true {
            clear()
            output("Choose a theme (↑/↓, Enter to apply, Esc/q to cancel)\n")
            let start = min(max(0, selected - visibleCount / 2), themes.count - visibleCount)
            for index in start..<(start + visibleCount) {
                output("\(index == selected ? "❯" : " ") \(themes[index])\n")
            }
            drawn = true
            guard let key = try readByte() else { return nil }
            switch key {
            case 10, 13: return themes[selected]
            case 3, 4, 113: return nil // Ctrl-C, Ctrl-D, q
            case 27:
                guard let prefix = try readByte(timeout: 100) else { return nil }
                if prefix == 91 || prefix == 79, let arrow = try readByte(timeout: 100) {
                    if arrow == 65 { selected = (selected + themes.count - 1) % themes.count }
                    if arrow == 66 { selected = (selected + 1) % themes.count }
                }
            default: break
            }
        }
    }

    private static func readByte(timeout: Int32? = nil) throws -> UInt8? {
        if let timeout {
            var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, timeout)
            if ready == 0 { return nil }
            if ready < 0 { throw OmacrazyError(description: "could not read terminal input") }
        }
        var byte: UInt8 = 0
        let count = Darwin.read(STDIN_FILENO, &byte, 1)
        if count == 0 { return nil }
        guard count == 1 else { throw OmacrazyError(description: "could not read terminal input") }
        return byte
    }
}
