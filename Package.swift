// swift-tools-version: 6.0
import Foundation
import PackageDescription

let developerDirectory: String = {
    if let override = ProcessInfo.processInfo.environment["DEVELOPER_DIR"], !override.isEmpty {
        return override
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    process.arguments = ["-p"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0,
           let path = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }
    } catch {
        // Fall back to the standard Command Line Tools location.
    }
    return "/Library/Developer/CommandLineTools"
}()

let testingFrameworkSearchPath = [
    "\(developerDirectory)/Library/Developer/Frameworks",
    "\(developerDirectory)/Platforms/MacOSX.platform/Developer/Library/Frameworks"
].first { FileManager.default.fileExists(atPath: "\($0)/Testing.framework") }

let testingInteropLibrarySearchPath = [
    "\(developerDirectory)/Library/Developer/usr/lib",
    "\(developerDirectory)/Platforms/MacOSX.platform/Developer/usr/lib"
].first { FileManager.default.fileExists(atPath: "\($0)/lib_TestingInterop.dylib") }

let testingRuntimeSearchPaths = [testingFrameworkSearchPath, testingInteropLibrarySearchPath].compactMap { $0 }
let testingLinkerFlags = ["-F", testingFrameworkSearchPath ?? ""] + testingRuntimeSearchPaths.flatMap {
    ["-Xlinker", "-rpath", "-Xlinker", $0]
}

let package = Package(
    name: "Omacrazy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "omacrazy", targets: ["Omacrazy"])
    ],
    targets: [
        .executableTarget(name: "Omacrazy"),
        .testTarget(
            name: "OmacrazyTests",
            dependencies: ["Omacrazy"],
            swiftSettings: testingFrameworkSearchPath.map { [.unsafeFlags(["-F", $0])] } ?? [],
            linkerSettings: testingFrameworkSearchPath.map { _ in [.unsafeFlags(testingLinkerFlags)] } ?? []
        )
    ]
)
