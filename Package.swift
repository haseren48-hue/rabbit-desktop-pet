// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RabbitDesktopPet",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "RabbitDesktopPet", targets: ["RabbitDesktopPet"])],
    targets: [
        .executableTarget(
            name: "RabbitDesktopPet",
            resources: [.process("Resources")]
        )
    ]
)
