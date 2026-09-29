// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ColdDown",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ThermalCore", type: .static, targets: ["ThermalCore"]),
        .library(name: "IntelSMC", type: .static, targets: ["IntelSMC"]),
        .library(name: "FlydigiHID", type: .static, targets: ["FlydigiHID"])
    ],
    targets: [
        .target(name: "ThermalCore"),
        .target(
            name: "AppleSiliconHIDBridge",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "IntelSMC",
            dependencies: ["ThermalCore", "AppleSiliconHIDBridge"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "FlydigiHID",
            dependencies: ["ThermalCore"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(
            name: "ColdDownTests",
            dependencies: ["ThermalCore", "IntelSMC", "FlydigiHID"],
            path: "Tests/ColdDownTests",
            // These need the ColdDownApp module and only run in the Xcode-hosted suite.
            exclude: ["Unit/FanConfigurationViewModelTests.swift", "Unit/SessionMarkerTests.swift"]
        )
    ],
    swiftLanguageModes: [.v6]
)
