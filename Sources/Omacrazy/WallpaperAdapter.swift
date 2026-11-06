import AppKit
import Foundation

struct WallpaperApplication {
    let imageName: String
    let screenCount: Int
}

enum WallpaperAdapter {
    @MainActor
    static func apply(themeName: String, themeRoot: URL) throws -> WallpaperApplication? {
        let fileManager = FileManager.default
        let sourceDirectory = themeRoot.appendingPathComponent("backgrounds", isDirectory: true)
        guard fileManager.fileExists(atPath: sourceDirectory.path) else { return nil }

        let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp"]
        let images = try fileManager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard let selectedImage = images.randomElement() else { return nil }

        let appSupport = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Omacrazy", isDirectory: true)
        let installedDirectory = appSupport
            .appendingPathComponent("themes/\(themeName)/backgrounds", isDirectory: true)
        try fileManager.createDirectory(at: installedDirectory, withIntermediateDirectories: true)
        let installedImage = installedDirectory.appendingPathComponent(selectedImage.lastPathComponent)
        try installImage(selectedImage, at: installedImage)

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw OmacrazyError(description: "macOS did not report any screens to set the wallpaper on")
        }

        let workspace = NSWorkspace.shared
        var appliedCount = 0
        var failures: [String] = []
        for (index, screen) in screens.enumerated() {
            do {
                let options = workspace.desktopImageOptions(for: screen) ?? [:]
                try workspace.setDesktopImageURL(installedImage, for: screen, options: options)
                appliedCount += 1
            } catch {
                failures.append("display \(index + 1): \(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            throw OmacrazyError(description: "set wallpaper on \(appliedCount)/\(screens.count) display(s); " + failures.joined(separator: "; "))
        }
        return WallpaperApplication(imageName: selectedImage.lastPathComponent, screenCount: appliedCount)
    }

    private static func installImage(_ source: URL, at destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            if try Data(contentsOf: source) == Data(contentsOf: destination) { return }
            let backup = destination.appendingPathExtension("omacrazy-backup")
            if !fileManager.fileExists(atPath: backup.path) {
                try fileManager.copyItem(at: destination, to: backup)
            }
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }
}
