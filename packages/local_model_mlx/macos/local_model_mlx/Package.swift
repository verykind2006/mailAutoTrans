// swift-tools-version: 5.9
// MailAutoTrans 本机翻译模型插件（Flutter 用 Swift Package Manager 编进 App）。
import PackageDescription

let package = Package(
    name: "local_model_mlx",
    // MLX 要求 macOS 14
    platforms: [.macOS("14.0")],
    products: [
        .library(name: "local-model-mlx", targets: ["local_model_mlx"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // 和 autoTransWhatsapp / vInput 同一个 MLX 版本（exact：API 在小版本间变过）
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", exact: "2.29.1"),
    ],
    targets: [
        .target(
            name: "local_model_mlx",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            ]
        )
    ]
)
