import Foundation

public struct ComplianceReport: Codable, Equatable {
    public var flags: [String]
    public var verdict: String
    public var details: [String]

    public init(flags: [String], verdict: String, details: [String] = []) {
        self.flags = flags
        self.verdict = verdict
        self.details = details
    }
}

public final class ComplianceService {
    private let piiRegex = try! NSRegularExpression(pattern: "\\b[0-9]{3}-[0-9]{2}-[0-9]{4}\\b")
    private let emailRegex = try! NSRegularExpression(pattern: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", options: [.caseInsensitive])
    private let phoneRegex = try! NSRegularExpression(pattern: "\\+?[0-9]{7,15}")
    private let bannedPhrases = ["hack", "bypass", "impersonate"]

    public init() {}

    public func scan(text: String? = nil, html: String? = nil, docID: String? = nil) -> ComplianceReport {
        let body = (html?.removingHTMLOccurrences() ?? "") + " " + (text ?? "")
        var flags: [String] = []
        var details: [String] = []

        if piiRegex.firstMatch(in: body, options: [], range: NSRange(location: 0, length: body.utf16.count)) != nil {
            flags.append("pii")
            details.append("Potential SSN detected")
        }
        if emailRegex.firstMatch(in: body, options: [], range: NSRange(location: 0, length: body.utf16.count)) != nil {
            flags.append("email")
            details.append("Email address present")
        }
        if phoneRegex.firstMatch(in: body, options: [], range: NSRange(location: 0, length: body.utf16.count)) != nil {
            flags.append("phone")
            details.append("Phone number present")
        }
        let lower = body.lowercased()
        let bannedHits = bannedPhrases.filter { lower.contains($0) }
        if !bannedHits.isEmpty {
            flags.append("policy")
            details.append("Contains restricted phrases: \(bannedHits.joined(separator: ", "))")
        }

        let verdict = flags.contains(where: { $0 == "pii" || $0 == "policy" }) ? "manual_review" : "ok"
        if let docID = docID { details.append("doc_id=\(docID)") }
        return ComplianceReport(flags: Array(Set(flags)), verdict: verdict, details: details)
    }

    public func sanitize(html: String) -> (cleanHTML: String, removed: [String]) {
        let pattern = "<(script|style)[^>]*>[\\s\\S]*?</\\1>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(location: 0, length: html.utf16.count)
        let clean = regex?.stringByReplacingMatches(in: html, options: [], range: range, withTemplate: "") ?? html
        let removed = clean == html ? [] : ["script/style"]
        return (clean, removed)
    }

    public func freeze(scope: String, reason: String) -> Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return scope == "persona" || scope == "all"
    }
}

private extension String {
    func removingHTMLOccurrences() -> String {
        let pattern = "<[^>]+>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: utf16.count)
        return regex?.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: " ") ?? self
    }
}
