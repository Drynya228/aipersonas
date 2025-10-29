import Foundation

public protocol Database {
    func save<T: Codable>(_ value: T, forKey key: String) throws
    func load<T: Codable>(_ type: T.Type, forKey key: String) throws -> T?
    func removeValue(forKey key: String) throws
}

public final class InMemoryDatabase: Database {
    private var store: [String: Data] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {}

    public func save<T: Codable>(_ value: T, forKey key: String) throws {
        let data = try encoder.encode(value)
        store[key] = data
    }

    public func load<T: Codable>(_ type: T.Type, forKey key: String) throws -> T? {
        guard let data = store[key] else { return nil }
        return try decoder.decode(T.self, from: data)
    }

    public func removeValue(forKey key: String) throws {
        store[key] = nil
    }
}

public final class FileBackedDatabase: Database {
    private let root: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default

    public init(rootDirectoryName: String = "AgentDesk") throws {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        root = base.appendingPathComponent(rootDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func save<T: Codable>(_ value: T, forKey key: String) throws {
        let data = try encoder.encode(value)
        let url = storageURL(for: key)
        try data.write(to: url, options: [.atomic])
    }

    public func load<T: Codable>(_ type: T.Type, forKey key: String) throws -> T? {
        let url = storageURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }

    public func removeValue(forKey key: String) throws {
        let url = storageURL(for: key)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func storageURL(for key: String) -> URL {
        root.appendingPathComponent("\(key).json", isDirectory: false)
    }
}
