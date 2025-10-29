import Foundation

public protocol ToolInvoking {
    func callTool(named name: String, arguments: [String: Any]) throws -> ToolCallResult
}

public struct ToolCallResult {
    public let name: String
    public let payload: Any

    public init(name: String, payload: Any) {
        self.name = name
        self.payload = payload
    }
}

public protocol SessionStorage {
    func append(message: SessionMessage) throws
    func history(for taskID: UUID) throws -> [SessionMessage]
    func replaceHistory(_ messages: [SessionMessage], for taskID: UUID) throws
    func removeAll(for taskID: UUID) throws
}

public final class InMemorySessionStorage: SessionStorage {
    private var messages: [UUID: [SessionMessage]] = [:]
    private let lock = NSLock()

    public init() {}

    public func append(message: SessionMessage) throws {
        lock.lock()
        defer { lock.unlock() }
        var history = messages[message.taskID, default: []]
        history.append(message)
        messages[message.taskID] = history
    }

    public func history(for taskID: UUID) throws -> [SessionMessage] {
        lock.lock()
        defer { lock.unlock() }
        return messages[taskID] ?? []
    }

    public func replaceHistory(_ messages: [SessionMessage], for taskID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        self.messages[taskID] = messages
    }

    public func removeAll(for taskID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        messages[taskID] = []
    }
}

public final class SessionManager {
    private let storage: SessionStorage
    private let toolInvoker: ToolInvoking
    private let contextCharacterLimit: Int

    public init(storage: SessionStorage,
                toolInvoker: ToolInvoking,
                contextCharacterLimit: Int = 8000) {
        self.storage = storage
        self.toolInvoker = toolInvoker
        self.contextCharacterLimit = contextCharacterLimit
    }

    @discardableResult
    public func send(message: SessionMessage) throws -> SessionMessage {
        var enriched = message
        enriched.timestamp = Date()
        try storage.append(message: enriched)

        if let toolCall = enriched.toolCall {
            _ = try toolInvoker.callTool(named: toolCall.name, arguments: toolCall.arguments.mapValues { $0.value })
        }

        try enforceContextLimit(for: enriched.taskID)
        return enriched
    }

    public func history(for taskID: UUID) throws -> [SessionMessage] {
        try storage.history(for: taskID)
    }

    public func clear(taskID: UUID) throws {
        try storage.removeAll(for: taskID)
    }

    private func enforceContextLimit(for taskID: UUID) throws {
        var history = try storage.history(for: taskID).sorted { $0.timestamp < $1.timestamp }
        var safetyCounter = 0
        while history.reduce(0, { $0 + $1.content.count }) > contextCharacterLimit,
              history.count > 2,
              safetyCounter < 5 {
            safetyCounter += 1
            let midpoint = max(1, history.count / 2)
            let head = Array(history.prefix(midpoint))
            let tail = Array(history.suffix(from: midpoint))
            var summaryText = summary(for: head)
            if summaryText.count > contextCharacterLimit {
                summaryText = String(summaryText.prefix(contextCharacterLimit))
            }
            let summaryMessage = SessionMessage(taskID: taskID,
                                                role: .system,
                                                content: summaryText,
                                                timestamp: Date())
            history = [summaryMessage] + tail
        }
        while history.reduce(0, { $0 + $1.content.count }) > contextCharacterLimit && history.count > 1 {
            if history.first?.role == .system && history.count > 1 {
                history.remove(at: 1)
            } else {
                history.removeFirst()
            }
        }
        try storage.replaceHistory(history, for: taskID)
    }

    private func summary(for messages: [SessionMessage]) -> String {
        guard !messages.isEmpty else { return "" }
        let roles = messages.map { $0.role.rawValue }.joined(separator: ", ")
        let excerpt = messages.prefix(2).map { "\($0.role.rawValue.capitalized): \($0.content.prefix(120))" }
            .joined(separator: " | ")
        return "[Context Summary] Roles: \(roles). Highlights: \(excerpt)…"
    }
}

public struct SessionMessage: Codable, Identifiable {
    public enum Role: String, Codable {
        case system
        case manager
        case worker
        case validator
        case advisor
        case user
    }

    public var id: UUID
    public var taskID: UUID
    public var role: Role
    public var content: String
    public var timestamp: Date
    public var toolCall: ToolCall?
    public var tokenEstimate: Int

    public init(id: UUID = UUID(),
                taskID: UUID,
                role: Role,
                content: String,
                timestamp: Date = .init(),
                toolCall: ToolCall? = nil,
                tokenEstimate: Int = 0) {
        self.id = id
        self.taskID = taskID
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCall = toolCall
        self.tokenEstimate = tokenEstimate
    }
}

public struct ToolCall: Codable {
    public var name: String
    public var arguments: [String: AnyCodable]

    public init(name: String, arguments: [String: AnyCodable]) {
        self.name = name
        self.arguments = arguments
    }
}

public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
