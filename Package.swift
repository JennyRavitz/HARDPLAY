// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "HARDPLAY", platforms: [.macOS(.v14)], targets: [.executableTarget(name: "HARDPLAY", path: "Sources", swiftSettings: [.swiftLanguageMode(.v5)])])
