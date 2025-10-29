import XCTest
@testable import AgentCore
@testable import ToolHub
@testable import RAG
@testable import RevenueWatch
@testable import Compliance
@testable import Payments
@testable import Voice

final class AgentDeskTests: XCTestCase {
    func testSessionManagerSummarisesLongContext() throws {
        let storage = InMemorySessionStorage()
        let manager = SessionManager(storage: storage, toolInvoker: ToolRegistry.shared, contextCharacterLimit: 80)
        let taskID = UUID()
        for idx in 0..<5 {
            let content = String(repeating: "message-\(idx) ", count: 5)
            try manager.send(message: SessionMessage(taskID: taskID, role: .manager, content: content))
        }
        let history = try manager.history(for: taskID)
        let total = history.reduce(0) { $0 + $1.content.count }
        XCTAssertLessThanOrEqual(total, 200)
        XCTAssertTrue(history.count < 5 || history.contains { $0.role == .system })
    }

    func testToolRegistryValidatesArguments() throws {
        let registry = ToolRegistry.shared
        XCTAssertThrowsError(try registry.callTool(named: "web.fetch", arguments: [:]))
        let result = try registry.callTool(named: "doc.format", arguments: ["input": "Hello", "style": "formal"])
        let payload = try XCTUnwrap(result.payload as? [String: String])
        XCTAssertTrue(payload["html"]?.contains("Hello") ?? false)
    }

    func testRAGServiceReturnsRankedChunks() throws {
        let rag = RAGService()
        let tmp = try temporaryFile(contents: "Swift AI makes Agents productive.")
        _ = rag.index(paths: [tmp.path], collection: "demo")
        let results = rag.retrieve(query: "agents productive", collections: ["demo"], k: 2)
        XCTAssertFalse(results.isEmpty)
        if results.count == 2 {
            XCTAssertGreaterThanOrEqual(results[0].score, results[1].score)
        }
    }

    func testComplianceDetectionAndSanitizer() {
        let service = ComplianceService()
        let report = service.scan(text: "Contact me at founder@example.com and let's hack the system")
        XCTAssertTrue(report.flags.contains("email"))
        XCTAssertTrue(report.flags.contains("policy"))
        XCTAssertEqual(report.verdict, "manual_review")
        let sanitized = service.sanitize(html: "<script>alert('x')</script><p>Ok</p>")
        XCTAssertTrue(sanitized.removed.contains("script/style"))
    }

    func testPaymentsLifecycle() {
        let service = PaymentsService()
        let invoice = service.createInvoice(clientID: "client", currency: "EUR", items: [InvoiceItem(name: "Work", qty: 2, price: 10)])
        XCTAssertEqual(invoice.status, .pending)
        XCTAssertEqual(service.events(for: invoice.id).count, 1)
        _ = service.settle(invoiceID: invoice.id, status: .paid)
        let updated = service.pollInvoice(id: invoice.id)
        XCTAssertEqual(updated?.status, .paid)
    }

    func testVoiceServiceStoresRecording() {
        let service = VoiceService()
        let taskID = UUID()
        let callID = service.startCall(for: taskID, personaID: nil)
        let record = service.endCall(callID: callID, transcript: "Hello")
        XCTAssertNotNil(record)
        XCTAssertEqual(service.recordings(for: taskID).count, 1)
    }

    func testRevenueDecisionsTriggered() {
        let service = RevenueMetricsService()
        let snapshot = RevenueSnapshot(jobsPerDay: 1.0,
                                       firstPassYield: 0.6,
                                       sla: 0.9,
                                       ebitda: 4.0,
                                       queueDepth: 2,
                                       tokenCostRate: 0.3,
                                       rpm: 5.0,
                                       acceptRate: 0.3,
                                       avgRevisionCost: 5.5,
                                       audioMinutes: 12)
        let decisions = service.evaluateThresholds(snapshot: snapshot)
        XCTAssertEqual(decisions.count, 3)
        _ = service.record(snapshot: snapshot)
        XCTAssertFalse(service.recentDecisions().isEmpty)
    }

    // MARK: - Helpers

    private func temporaryFile(contents: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try contents.data(using: .utf8)?.write(to: url)
        return url
    }
}
