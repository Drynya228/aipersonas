// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentDesk",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AgentCore", targets: ["AgentCore"]),
        .library(name: "ToolHub", targets: ["ToolHub"]),
        .library(name: "Voice", targets: ["Voice"]),
        .library(name: "RAG", targets: ["RAG"]),
        .library(name: "Storage", targets: ["Storage"]),
        .library(name: "RevenueWatch", targets: ["RevenueWatch"]),
        .library(name: "Payments", targets: ["Payments"]),
        .library(name: "Compliance", targets: ["Compliance"]),
    ],
    targets: [
        .target(name: "AgentCore", dependencies: [], path: "AgentCore"),
        .target(name: "ToolHub", dependencies: ["AgentCore", "RAG"], path: "ToolHub"),
        .target(name: "Voice", dependencies: ["AgentCore"], path: "Voice"),
        .target(name: "RAG", dependencies: [], path: "RAG"),
        .target(name: "Storage", dependencies: [], path: "Storage"),
        .target(name: "RevenueWatch", dependencies: ["AgentCore"], path: "RevenueWatch"),
        .target(name: "Payments", dependencies: [], path: "Payments"),
        .target(name: "Compliance", dependencies: [], path: "Compliance"),
        .testTarget(name: "AgentDeskTests", dependencies: ["AgentCore", "ToolHub", "RAG", "RevenueWatch", "Compliance", "Payments", "Voice"], path: "Tests")
    ]
)
