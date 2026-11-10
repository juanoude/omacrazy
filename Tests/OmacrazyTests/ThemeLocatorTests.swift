import Foundation
import Testing
@testable import Omacrazy

@Test func installedThemesTakePrecedenceOverWorkingDirectory() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let installed = root.appendingPathComponent("installed/themes")
    let checkout = root.appendingPathComponent("checkout")
    try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: checkout.appendingPathComponent("themes"), withIntermediateDirectories: true)
    #expect(try ThemeLocator.themesDirectory(installedDirectory: installed, searchStarts: [checkout]) == installed)
    #expect(try ThemeLocator.themesDirectory(installedDirectory: installed, searchStarts: []) == installed)
}

@Test func uninstalledThemesFallBackToCheckoutFromNestedDirectory() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let themes = root.appendingPathComponent("themes", isDirectory: true)
    let nested = root.appendingPathComponent("nested/working", isDirectory: true)
    try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    #expect(try ThemeLocator.themesDirectory(installedDirectory: root.appendingPathComponent("missing"), searchStarts: [nested]) == themes)
}

@Test func missingThemeDirectoryReportsFailureIncludingRegularFile() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("themes")
    try Data().write(to: file)
    #expect(throws: OmacrazyError.self) {
        try ThemeLocator.themesDirectory(installedDirectory: file, searchStarts: [])
    }
}
