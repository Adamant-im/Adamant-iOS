// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "BitcoinKit",
//    platforms: [
//        .iOS(.v10)
//    ],
    products: [
        .library(name: "BitcoinKit", targets: ["BitcoinKit"])
    ],
    dependencies: [
//        .package(url: "https://github.com/krzyzanowskim/OpenSSL.git", from: "1.1.180"),
//        .package(url: "https://github.com/Boilertalk/secp256k1.swift", from: "0.1.0"),
//        .package(url: "https://github.com/vapor-community/random.git", from: "1.2.0")
        .package(url: "https://github.com/krzyzanowskim/OpenSSL.git", .upToNextMinor(from: "1.1.180")),
//        .package(url: "https://github.com/Boilertalk/secp256k1.swift", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/vapor-community/random.git", .upToNextMinor(from: "1.2.0"))
    ],
    targets: [
        .target(name: "secp256k1.c"),
        .target(
            name: "BitcoinKit",
            dependencies: ["BitcoinKitPrivate", "secp256k1.c", "Random"]
        ),
        .target(
            name: "BitcoinKitPrivate",
            dependencies: ["OpenSSL", "secp256k1.c"]
        )
    ]
)