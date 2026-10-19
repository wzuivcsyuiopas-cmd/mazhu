// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-only
import PackageDescription
let package = Package(name: "TuMa", platforms: [.macOS(.v26)], products: [.executable(name: "TuMa", targets: ["TuMa"])], targets: [.executableTarget(name: "TuMa", path: "Sources/TuMa")], swiftLanguageModes: [.v5])
