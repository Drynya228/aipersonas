import Foundation
import AgentCore
import RAG

public enum ToolError: Error, CustomStringConvertible {
    case unsupportedTool(String)
    case invalidArguments(String)

    public var description: String {
        switch self {
        case .unsupportedTool(let name):
            return "Unsupported tool: \(name)"
        case .invalidArguments(let reason):
            return "Invalid arguments: \(reason)"
        }
    }
}

public enum ToolParameterType {
    case string
    case int
    case double
    case bool
    case stringArray
    case anyArray
    case stringDictionary
    case anyDictionary

    func validate(value: Any) -> Bool {
        switch self {
        case .string:
            return value is String
        case .int:
            return value is Int
        case .double:
            return (value is Double) || (value is Float) || (value is Int)
        case .bool:
            return value is Bool
        case .stringArray:
            return (value as? [String]) != nil
        case .anyArray:
            return value is [Any]
        case .stringDictionary:
            return (value as? [String: String]) != nil
        case .anyDictionary:
            return value is [String: Any]
        }
    }
}

public struct ToolParameter {
    public let name: String
    public let type: ToolParameterType
    public let required: Bool
    public let description: String

    public init(name: String, type: ToolParameterType, required: Bool = true, description: String) {
        self.name = name
        self.type = type
        self.required = required
        self.description = description
    }
}

public struct ToolDescriptor {
    public let name: String
    public let summary: String
    public let parameters: [ToolParameter]
    public let executor: ([String: Any]) throws -> Any

    public init(name: String, summary: String, parameters: [ToolParameter], executor: @escaping ([String: Any]) throws -> Any) {
        self.name = name
        self.summary = summary
        self.parameters = parameters
        self.executor = executor
    }
}

public final class ToolRegistry: ToolInvoking {
    public static let shared = ToolRegistry()

    private var registry: [String: ToolDescriptor] = [:]
    private let ragService = RAGService()

    private init() {
        registerCoreTools()
    }

    public func register(_ descriptor: ToolDescriptor) {
        registry[descriptor.name] = descriptor
    }

    public func callTool(named name: String, arguments: [String: Any]) throws -> ToolCallResult {
        guard let descriptor = registry[name] else {
            throw ToolError.unsupportedTool(name)
        }
        let payload = try descriptor.executor(try validatedArguments(arguments, descriptor: descriptor))
        return ToolCallResult(name: name, payload: payload)
    }

    private func validatedArguments(_ provided: [String: Any], descriptor: ToolDescriptor) throws -> [String: Any] {
        var processed: [String: Any] = [:]
        for parameter in descriptor.parameters {
            let value = provided[parameter.name]
            if value == nil && !parameter.required {
                continue
            }
            guard let unwrapped = value else {
                throw ToolError.invalidArguments("Missing required parameter \(parameter.name)")
            }
            guard parameter.type.validate(value: unwrapped) else {
                throw ToolError.invalidArguments("Parameter \(parameter.name) expected \(parameter.type) but received \(type(of: unwrapped))")
            }
            processed[parameter.name] = unwrapped
        }
        return processed
    }

    private func registerCoreTools() {
        register(ToolDescriptor(name: "web.fetch",
                                summary: "Safely fetches public content via HTTPS using GET.",
                                parameters: [
                                    ToolParameter(name: "url", type: .string, description: "Absolute https URL."),
                                    ToolParameter(name: "mode", type: .string, required: false, description: "html|text|pdf")
                                ]) { args in
            let url = args["url"] as! String
            guard url.lowercased().hasPrefix("https://") else {
                throw ToolError.invalidArguments("Only https:// URLs are permitted")
            }
            let mode = (args["mode"] as? String) ?? "text"
            let content = "Fetched placeholder content from \(url) in mode \(mode)."
            return [
                "content": content,
                "meta": [
                    "status": 200,
                    "finalUrl": url
                ]
            ]
        })

        register(ToolDescriptor(name: "doc.format",
                                summary: "Formats markdown/HTML fragments into styled HTML articles.",
                                parameters: [
                                    ToolParameter(name: "input", type: .string, description: "Markdown or HTML input."),
                                    ToolParameter(name: "style", type: .string, description: "Style preset key.")
                                ]) { args in
            let input = args["input"] as! String
            let style = args["style"] as! String
            let html = "<article data-style=\"\(style)\">\n  \(input)\n</article>"
            return ["html": html]
        })

        register(ToolDescriptor(name: "rag.index",
                                summary: "Indexes supplied file paths into the local FAISS-like store.",
                                parameters: [
                                    ToolParameter(name: "paths", type: .stringArray, description: "File paths to index."),
                                    ToolParameter(name: "collection", type: .string, description: "Collection identifier.")
                                ]) { [weak self] args in
            guard let paths = args["paths"] as? [String],
                  let collection = args["collection"] as? String else { return [:] }
            let stats = self?.ragService.index(paths: paths, collection: collection)
            return ["stats": ["files": stats?.files ?? 0, "chunks": stats?.chunks ?? 0]]
        })

        register(ToolDescriptor(name: "rag.retrieve",
                                summary: "Retrieves relevant knowledge base chunks for grounding.",
                                parameters: [
                                    ToolParameter(name: "query", type: .string, description: "User query or task brief."),
                                    ToolParameter(name: "collections", type: .stringArray, description: "Collections to search."),
                                    ToolParameter(name: "k", type: .int, required: false, description: "Number of chunks (default 3).")
                                ]) { [weak self] args in
            guard let query = args["query"] as? String,
                  let collections = args["collections"] as? [String] else { return [:] }
            let k = (args["k"] as? Int) ?? 3
            let results = self?.ragService.retrieve(query: query, collections: collections, k: k) ?? []
            let encoded = results.map { chunk in
                [
                    "text": chunk.text,
                    "source": chunk.source,
                    "score": chunk.score
                ]
            }
            return ["chunks": encoded]
        })

        register(ToolDescriptor(name: "qa.style_text",
                                summary: "Runs checklist-driven QA on textual artefacts.",
                                parameters: [
                                    ToolParameter(name: "doc", type: .string, description: "Document body."),
                                    ToolParameter(name: "checklist", type: .string, description: "Checklist path or YAML."),
                                ]) { args in
            let doc = args["doc"] as! String
            let findings: [[String: Any]]
            if doc.lowercased().contains("todo") {
                findings = [["type": "tone", "msg": "Document contains TODO markers."]]
            } else {
                findings = []
            }
            let verdict = findings.isEmpty ? "accept" : "revise"
            return ["findings": findings, "verdict": verdict]
        })

        register(ToolDescriptor(name: "git.patch",
                                summary: "Applies a validated git patch via safe shell wrapper.",
                                parameters: [
                                    ToolParameter(name: "repo_path", type: .string, description: "Repository root."),
                                    ToolParameter(name: "patch", type: .string, description: "Unified diff patch."),
                                    ToolParameter(name: "message", type: .string, description: "Commit message."),
                                ]) { args in
            let message = args["message"] as! String
            return ["commit": "mocked-commit-for-\(message.replacingOccurrences(of: " ", with: "-"))"]
        })

        register(ToolDescriptor(name: "email.draft",
                                summary: "Creates an email draft for delivery or follow-up.",
                                parameters: [
                                    ToolParameter(name: "to", type: .stringArray, description: "Recipient list."),
                                    ToolParameter(name: "subject", type: .string, description: "Email subject."),
                                    ToolParameter(name: "html", type: .string, description: "Email body HTML."),
                                    ToolParameter(name: "attachments", type: .stringArray, required: false, description: "Attachment file paths."),
                                ]) { args in
            let subject = args["subject"] as! String
            let recipients = args["to"] as! [String]
            return [
                "draft_id": "draft-\(abs(subject.hashValue))",
                "recipients": recipients
            ]
        })

        register(ToolDescriptor(name: "security.sanitize",
                                summary: "Sanitises HTML output removing unsafe attributes.",
                                parameters: [
                                    ToolParameter(name: "html", type: .string, description: "Raw HTML."),
                                ]) { args in
            let html = args["html"] as! String
            let clean = html.replacingOccurrences(of: "script", with: "")
            let flags = clean == html ? [] : ["removed_script"]
            return [
                "clean_html": clean,
                "report": ["flags": flags]
            ]
        })

        register(ToolDescriptor(name: "market.search",
                                summary: "Searches authorised marketplaces for compliant leads.",
                                parameters: [
                                    ToolParameter(name: "query", type: .string, description: "Search keywords."),
                                    ToolParameter(name: "locales", type: .stringArray, required: false, description: "Target locales."),
                                    ToolParameter(name: "price_min", type: .double, required: false, description: "Minimum price."),
                                    ToolParameter(name: "deadline_min_hours", type: .int, required: false, description: "Minimum deadline lead."),
                                    ToolParameter(name: "size_max_minutes", type: .int, required: false, description: "Maximum duration minutes."),
                                    ToolParameter(name: "verified_only", type: .bool, required: false, description: "Verified clients only."),
                                ]) { args in
            let query = args["query"] as! String
            return [
                "leads": [
                    [
                        "id": UUID().uuidString,
                        "title": "\(query) copy refresh",
                        "budget": 180,
                        "deadline": ISO8601DateFormatter().string(from: Date().addingTimeInterval(7200)),
                        "url": "https://market.example/jobs/\(UUID().uuidString)",
                        "locale": (args["locales"] as? [String])?.first ?? "en-US",
                        "type": "translate"
                    ]
                ]
            ]
        })

        register(ToolDescriptor(name: "market.propose",
                                summary: "Submits a proposal in live or dry-run mode.",
                                parameters: [
                                    ToolParameter(name: "lead_id", type: .string, description: "Lead identifier."),
                                    ToolParameter(name: "persona_id", type: .string, description: "Persona submitting."),
                                    ToolParameter(name: "pitch_md", type: .string, description: "Markdown pitch."),
                                    ToolParameter(name: "samples", type: .stringArray, required: false, description: "Portfolio samples."),
                                    ToolParameter(name: "price", type: .double, description: "Offered price."),
                                    ToolParameter(name: "deadline_hours", type: .int, description: "Hours until delivery."),
                                ]) { _ in
            return ["status": "sent", "url": "https://market.example/proposals/\(UUID().uuidString)"]
        })

        register(ToolDescriptor(name: "market.status",
                                summary: "Fetches the latest status of a submitted proposal.",
                                parameters: [
                                    ToolParameter(name: "lead_id", type: .string, description: "Lead identifier."),
                                ]) { _ in
            return ["state": "open"]
        })

        register(ToolDescriptor(name: "metrics.upsert_job",
                                summary: "Upserts metrics for a finished or in-flight job.",
                                parameters: [
                                    ToolParameter(name: "job_id", type: .string, description: "Job identifier."),
                                    ToolParameter(name: "persona_id", type: .string, description: "Persona responsible."),
                                    ToolParameter(name: "started_at", type: .string, description: "ISO8601 start time."),
                                    ToolParameter(name: "finished_at", type: .string, required: false, description: "ISO8601 finish time."),
                                    ToolParameter(name: "tokens", type: .int, required: false, description: "Token usage."),
                                    ToolParameter(name: "audio_minutes", type: .double, required: false, description: "Audio minutes consumed."),
                                    ToolParameter(name: "price", type: .double, required: false, description: "Price charged."),
                                    ToolParameter(name: "revisions", type: .int, required: false, description: "Revision count."),
                                ]) { _ in
            return ["ok": true]
        })

        register(ToolDescriptor(name: "metrics.snapshot",
                                summary: "Returns RPM, accept rate and cost metrics.",
                                parameters: [
                                    ToolParameter(name: "window", type: .string, description: "1d|7d")
                                ]) { args in
            let window = (args["window"] as? String) ?? "1d"
            let rpm = window == "1d" ? 7.2 : 6.8
            return [
                "rpm": rpm,
                "accept_rate": 0.71,
                "queue_depth": 5,
                "avg_revision_cost": 3.1,
                "token_cost_rate": 0.22
            ]
        })

        register(ToolDescriptor(name: "routing.rebalance",
                                summary: "Suggests new persona routing based on KPI thresholds.",
                                parameters: [
                                    ToolParameter(name: "targets", type: .stringArray, description: "Persona IDs or segments."),
                                    ToolParameter(name: "persona_cap", type: .int, required: false, description: "Max concurrent jobs per persona."),
                                ]) { _ in
            return ["ok": true]
        })

        register(ToolDescriptor(name: "billing.create_invoice",
                                summary: "Creates an invoice draft with compliant line items.",
                                parameters: [
                                    ToolParameter(name: "client_id", type: .string, description: "Client identifier."),
                                    ToolParameter(name: "currency", type: .string, description: "Currency code."),
                                    ToolParameter(name: "items", type: .anyArray, description: "Line items."),
                                ]) { _ in
            return [
                "invoice_id": UUID().uuidString,
                "pay_url": "https://payments.example/pay/\(UUID().uuidString)"
            ]
        })

        register(ToolDescriptor(name: "billing.poll",
                                summary: "Polls invoice status via the compliant API.",
                                parameters: [
                                    ToolParameter(name: "invoice_id", type: .string, description: "Invoice identifier."),
                                ]) { _ in
            return ["status": "paid", "amount": 120.0]
        })

        register(ToolDescriptor(name: "tax.issue_receipt",
                                summary: "Issues a fiscal receipt for a settled invoice.",
                                parameters: [
                                    ToolParameter(name: "invoice_id", type: .string, description: "Invoice identifier."),
                                    ToolParameter(name: "payer", type: .anyDictionary, description: "Payer info."),
                                    ToolParameter(name: "amount", type: .double, description: "Amount paid."),
                                    ToolParameter(name: "description", type: .string, description: "Receipt description."),
                                ]) { args in
            let invoiceID = args["invoice_id"] as! String
            return [
                "receipt_id": "rcpt-\(invoiceID)",
                "url": "https://payments.example/receipts/\(invoiceID)"
            ]
        })

        register(ToolDescriptor(name: "compliance.scan",
                                summary: "Runs a lightweight compliance scan for risky content.",
                                parameters: [
                                    ToolParameter(name: "text", type: .string, required: false, description: "Plain text body."),
                                    ToolParameter(name: "html", type: .string, required: false, description: "HTML body."),
                                    ToolParameter(name: "doc_id", type: .string, required: false, description: "Document identifier."),
                                ]) { args in
            let text = (args["text"] as? String) ?? (args["html"] as? String) ?? ""
            let hasPII = text.range(of: "\\b[0-9]{3}-[0-9]{2}-[0-9]{4}\\b", options: .regularExpression) != nil
            let flags = hasPII ? ["pii"] : []
            let verdict = hasPII ? "manual_review" : "ok"
            return ["flags": flags, "verdict": verdict]
        })

        register(ToolDescriptor(name: "admin.freeze",
                                summary: "Freezes persona or entire fleet with justification.",
                                parameters: [
                                    ToolParameter(name: "scope", type: .string, description: "persona|all"),
                                    ToolParameter(name: "reason", type: .string, description: "Justification."),
                                ]) { args in
            let reason = args["reason"] as! String
            return ["ok": !reason.trimmingCharacters(in: .whitespaces).isEmpty]
        })
    }
}
