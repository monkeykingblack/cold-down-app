// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ColdDown",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ThermalCore", type: .static, targets: ["ThermalCore"]),
        .library(name: "IntelSMC", type: .static, targets: ["IntelSMC"]),
        .library(name: "FlydigiHID", type: .static, targets: ["FlydigiHID"]),
        .library(name: "ColdDownShared", type: .static, targets: ["ColdDownShared"])
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
        .target(name: "ColdDownShared", dependencies: ["ThermalCore"]),
        // The helper's service layer, built here only so it can be tested; the Xcode helper target compiles
        // the same folder (plus main.swift) into the shipping launch daemon.
        .target(
            name: "ColdDownHelperCore",
            dependencies: ["ThermalCore", "IntelSMC", "ColdDownShared"],
            path: "Sources/ColdDownHelper",
            exclude: ["main.swift", "Resources", "ColdDownHelper.entitlements"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(
            name: "ColdDownTests",
            dependencies: ["ThermalCore", "IntelSMC", "FlydigiHID", "ColdDownShared"],
            path: "Tests/ColdDownTests",
            // These need the ColdDownApp module and only run in the Xcode-hosted suite.
            exclude: [
                "Unit/FanConfigurationViewModelTests.swift", "Unit/HelperAutoRegistrationTests.swift",
                "Unit/SessionMarkerTests.swift"
            ]
        ),
        .testTarget(
            name: "ColdDownHelperTests",
            dependencies: ["ColdDownHelperCore", "ThermalCore", "ColdDownShared"],
            path: "Tests/ColdDownHelperTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
