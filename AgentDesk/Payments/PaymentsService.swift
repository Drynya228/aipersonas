import Foundation

public struct InvoiceItem: Codable, Equatable {
    public var name: String
    public var qty: Int
    public var price: Double

    public init(name: String, qty: Int, price: Double) {
        self.name = name
        self.qty = qty
        self.price = price
    }
}

public struct Invoice: Codable, Equatable {
    public enum Status: String, Codable {
        case pending
        case paid
        case failed
    }

    public var id: String
    public var payURL: URL
    public var status: Status
    public var currency: String
    public var amount: Double
    public var issuedAt: Date
    public var lineItems: [InvoiceItem]

    public init(id: String,
                payURL: URL,
                status: Status,
                currency: String,
                amount: Double,
                issuedAt: Date = .init(),
                lineItems: [InvoiceItem]) {
        self.id = id
        self.payURL = payURL
        self.status = status
        self.currency = currency
        self.amount = amount
        self.issuedAt = issuedAt
        self.lineItems = lineItems
    }
}

public struct PaymentEvent: Codable, Equatable {
    public var id: UUID
    public var invoiceID: String
    public var status: Invoice.Status
    public var createdAt: Date
    public var metadata: [String: String]

    public init(id: UUID = UUID(), invoiceID: String, status: Invoice.Status, createdAt: Date = .init(), metadata: [String: String] = [:]) {
        self.id = id
        self.invoiceID = invoiceID
        self.status = status
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public final class PaymentsService {
    private var invoices: [String: Invoice] = [:]
    private var events: [PaymentEvent] = []
    private let lock = NSLock()

    public init() {}

    @discardableResult
    public func createInvoice(clientID: String, currency: String, items: [InvoiceItem]) -> Invoice {
        let amount = items.reduce(0) { $0 + (Double($1.qty) * $1.price) }
        let invoice = Invoice(id: UUID().uuidString,
                              payURL: URL(string: "https://payments.example/pay/\(UUID().uuidString)")!,
                              status: .pending,
                              currency: currency,
                              amount: amount,
                              lineItems: items)
        lock.lock()
        invoices[invoice.id] = invoice
        events.append(PaymentEvent(invoiceID: invoice.id, status: .pending, metadata: ["client_id": clientID]))
        lock.unlock()
        return invoice
    }

    public func pollInvoice(id: String) -> Invoice? {
        lock.lock()
        defer { lock.unlock() }
        return invoices[id]
    }

    @discardableResult
    public func settle(invoiceID: String, status: Invoice.Status, metadata: [String: String] = [:]) -> Invoice? {
        lock.lock()
        defer { lock.unlock() }
        guard var invoice = invoices[invoiceID] else { return nil }
        invoice.status = status
        invoices[invoiceID] = invoice
        events.append(PaymentEvent(invoiceID: invoiceID, status: status, metadata: metadata))
        return invoice
    }

    public func events(for invoiceID: String) -> [PaymentEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events.filter { $0.invoiceID == invoiceID }
    }
}
