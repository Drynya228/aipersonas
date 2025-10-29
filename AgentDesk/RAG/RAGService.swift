import Foundation

public struct RAGChunk: Codable, Equatable {
    public var id: UUID
    public var text: String
    public var source: String
    public var score: Double

    public init(id: UUID = UUID(), text: String, source: String, score: Double) {
        self.id = id
        self.text = text
        self.source = source
        self.score = score
    }
}

public struct RAGDocument: Codable, Equatable {
    public var path: String
    public var collection: String
    public var chunks: [RAGChunk]
}

public final class RAGService {
    private var documents: [String: [RAGDocument]] = [:]
    private let queue = DispatchQueue(label: "ai.agentdesk.rag", qos: .userInitiated)

    public init() {}

    @discardableResult
    public func index(paths: [String], collection: String) -> (files: Int, chunks: Int) {
        var inserted: [RAGDocument] = []
        for path in paths {
            let content = (try? String(contentsOfFile: path)) ?? "Document placeholder for \(path)"
            let chunks = buildChunks(from: content, source: path)
            inserted.append(RAGDocument(path: path, collection: collection, chunks: chunks))
        }
        queue.sync {
            documents[collection, default: []] += inserted
        }
        let chunkCount = inserted.reduce(0) { $0 + $1.chunks.count }
        return (inserted.count, chunkCount)
    }

    public func retrieve(query: String, collections: [String], k: Int = 3) -> [RAGChunk] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let pool = queue.sync { collections.flatMap { documents[$0] ?? [] }.flatMap { $0.chunks } }
        let ranked = pool.map { chunk -> RAGChunk in
            let score = relevanceScore(for: query, chunk: chunk)
            return RAGChunk(id: chunk.id, text: chunk.text, source: chunk.source, score: score)
        }.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.text.count < rhs.text.count
            }
            return lhs.score > rhs.score
        }
        return Array(ranked.prefix(max(1, k)))
    }

    private func buildChunks(from content: String, source: String) -> [RAGChunk] {
        let sentences = content.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if sentences.isEmpty {
            return [RAGChunk(text: content.prefix(280).description, source: source, score: 0.0)]
        }
        return sentences.chunked(into: 3).map { group in
            let text = group.joined(separator: ". ")
            return RAGChunk(text: text, source: source, score: 0.0)
        }
    }

    private func relevanceScore(for query: String, chunk: RAGChunk) -> Double {
        let queryTokens = tokenise(query)
        let chunkTokens = tokenise(chunk.text)
        guard !chunkTokens.isEmpty else { return 0.0 }
        let matches = queryTokens.filter { chunkTokens.contains($0) }
        return Double(matches.count) / Double(chunkTokens.count)
    }

    private func tokenise(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        var result: [[Element]] = []
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            result.append(Array(self[index..<end]))
            index += size
        }
        return result
    }
}
