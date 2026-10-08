// swift-tools-version: 5.9
// 方便在 Mac 上直接 `swift run` 預覽。正式的 iOS + macOS App 請參考 README 建立 Xcode 專案。
import PackageDescription

let package = Package(
    name: "AssetBook",
    defaultLocalization: "zh-Hant",
    platforms: [.macOS("15.0"), .iOS("18.0")],
    targets: [
        .executableTarget(name: "AssetBook", path: "Sources/AssetBook")
    ]
)
