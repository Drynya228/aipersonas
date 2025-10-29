import SwiftUI
import AgentCore
import ToolHub
import Voice
import Payments
import Compliance
import RevenueWatch
import RAG

@main
struct AgentDeskApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .commands {
            CommandMenu("AgentDesk") {
                Button("Refresh Metrics") {
                    appState.refreshMetrics()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

final class AppState: ObservableObject {
    @Published var section: AppSection = .dashboard
    @Published var metricsSnapshot: RevenueSnapshot
    @Published var revenueDecisions: [RevenueDecision]
    @Published var personas: [Persona]
    @Published var tasks: [Task]
    @Published var artifacts: [Artifact]
    @Published var settings: AppSettings
    @Published var selectedPersona: Persona?
    @Published var selectedTaskID: UUID?
    @Published var callRecords: [CallRecord]
    @Published var ragCollections: [String: (files: Int, chunks: Int)]
    @Published var sessionHistory: [UUID: [SessionMessage]]
    @Published var lastInvoice: Invoice?
    @Published var lastInvoiceEvents: [PaymentEvent]
    @Published var lastComplianceReport: ComplianceReport?

    private let sessionManager: SessionManager
    private let toolRegistry: ToolRegistry
    private let voiceService = VoiceService()
    private let paymentsService = PaymentsService()
    private let revenueService = RevenueMetricsService()
    private let complianceService = ComplianceService()
    private let ragService = RAGService()

    init() {
        toolRegistry = ToolRegistry.shared
        sessionManager = SessionManager(storage: InMemorySessionStorage(), toolInvoker: toolRegistry)
        let loadedPersonas = AppState.loadPersonasFromDisk()
        personas = loadedPersonas
        tasks = Task.sample(personaIDs: loadedPersonas.map { $0.id })
        artifacts = tasks.flatMap { Artifact.sample(for: $0) }
        settings = AppSettings()
        metricsSnapshot = RevenueSnapshot.placeholder
        revenueDecisions = []
        callRecords = []
        ragCollections = [:]
        sessionHistory = [:]
        lastInvoiceEvents = []
        refreshMetrics()
    }

    func refreshMetrics() {
        let snapshot = revenueService.snapshot(window: .oneDay)
        metricsSnapshot = snapshot
        _ = revenueService.record(snapshot: snapshot)
        revenueDecisions = revenueService.recentDecisions()
    }

    func snapshot(window: RevenueSnapshot.Window) -> RevenueSnapshot {
        revenueService.snapshot(window: window)
    }

    func addPersona(_ persona: Persona) {
        personas.append(persona)
    }

    func previewVoice(for persona: Persona) -> URL {
        voiceService.previewSpeech(for: persona, text: persona.samplePrompt.isEmpty ? "Привет! Я \(persona.name)." : persona.samplePrompt)
    }

    func tasks(in stage: TaskStage) -> [Task] {
        tasks.filter { $0.stage == stage }
    }

    func advance(task: Task) {
        guard let index = tasks.firstIndex(of: task) else { return }
        let nextStage: TaskStage
        switch task.stage {
        case .intake: nextStage = .inProgress
        case .inProgress: nextStage = .validate
        case .validate: nextStage = .deliver
        case .deliver: nextStage = .deliver
        }
        tasks[index].stage = nextStage
        tasks[index].updatedAt = Date()
    }

    func send(message: String, role: SessionMessage.Role, for task: Task) {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let msg = SessionMessage(taskID: task.id, role: role, content: message, tokenEstimate: message.count / 4)
        if let stored = try? sessionManager.send(message: msg) {
            var history = sessionHistory[task.id, default: []]
            history.append(stored)
            sessionHistory[task.id] = history
        }
    }

    func messages(for task: Task) -> [SessionMessage] {
        if let cached = sessionHistory[task.id] {
            return cached.sorted { $0.timestamp < $1.timestamp }
        }
        if let history = try? sessionManager.history(for: task.id) {
            sessionHistory[task.id] = history
            return history
        }
        return []
    }

    @discardableResult
    func simulateCall(for task: Task, persona: Persona?) -> CallRecord? {
        let callID = voiceService.startCall(for: task.id, personaID: persona?.id)
        let transcript = "Call between \(persona?.name ?? "Team") and client about \(task.title)."
        guard let record = voiceService.endCall(callID: callID, transcript: transcript) else { return nil }
        callRecords.append(record)
        return record
    }

    func recordings(for task: Task) -> [CallRecord] {
        voiceService.recordings(for: task.id)
    }

    func indexDocuments(paths: [String], collection: String) {
        let filtered = paths.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !filtered.isEmpty else { return }
        let stats = ragService.index(paths: filtered, collection: collection)
        ragCollections[collection] = stats
    }

    func retrieveDocuments(query: String, collections: [String], k: Int = 3) -> [RAGChunk] {
        ragService.retrieve(query: query, collections: collections, k: k)
    }

    func runComplianceScan(text: String) {
        lastComplianceReport = complianceService.scan(text: text)
    }

    func sanitize(html: String) -> (String, [String]) {
        complianceService.sanitize(html: html)
    }

    func update(settings: AppSettings) {
        self.settings = settings
    }

    func issueInvoice(for task: Task) {
        let items = [InvoiceItem(name: task.title, qty: 1, price: Double(task.budgetMinutes) / 2.0)]
        let invoice = paymentsService.createInvoice(clientID: task.client, currency: "EUR", items: items)
        lastInvoice = invoice
        lastInvoiceEvents = paymentsService.events(for: invoice.id)
    }

    func settleInvoice() {
        guard let invoice = lastInvoice else { return }
        _ = paymentsService.settle(invoiceID: invoice.id, status: .paid, metadata: ["source": "webhook-sim"])
        lastInvoice = paymentsService.pollInvoice(id: invoice.id)
        lastInvoiceEvents = paymentsService.events(for: invoice.id)
    }

    func exportDelivery(for task: Task) -> URL? {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        let filename = "delivery-\(task.id).zip"
        let url = directory.appendingPathComponent(filename)
        let summary = "Delivery package for \(task.title) generated at \(Date())."
        try? summary.data(using: .utf8)?.write(to: url)
        return url
    }

    private static func loadPersonasFromDisk() -> [Persona] {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Docs/personas", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else {
            return AppState.fallbackPersonas
        }
        let decoder = JSONDecoder()
        var personas: [Persona] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let persona = try? decoder.decode(Persona.self, from: data) {
                personas.append(persona)
            }
        }
        return personas.isEmpty ? AppState.fallbackPersonas : personas
    }

    private static var fallbackPersonas: [Persona] {
        [
            Persona(name: "Manager", role: "manager", tone: "Strategic", voicePreset: "alloy", voiceRate: 1.0, skills: ["briefing"], toolsAllowed: ["web.fetch"], ragCollections: ["default"], constraints: ["no_pii"], samplePrompt: "Планирую спринты и гарантирую прибыль."),
            Persona(name: "Worker", role: "worker", tone: "Friendly", voicePreset: "verse", voiceRate: 1.05, skills: ["copy"], toolsAllowed: ["doc.format"], ragCollections: ["default"], constraints: ["card<=90m"], samplePrompt: "Создаю драфты и быстро адаптируюсь."),
            Persona(name: "Validator", role: "validator", tone: "Direct", voicePreset: "nexus", voiceRate: 0.95, skills: ["qa"], toolsAllowed: ["qa.style_text"], ragCollections: ["default"], constraints: ["strict-checklist"], samplePrompt: "Закрываю задачи с минимальными правками.")
        ]
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case personas
    case tasks
    case chat
    case artifacts
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .personas: return "Personas"
        case .tasks: return "Tasks"
        case .chat: return "Chat & Calls"
        case .artifacts: return "Artifacts"
        case .settings: return "Settings"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SidebarView(selection: $appState.section)
        } detail: {
            switch appState.section {
            case .dashboard:
                DashboardView(metrics: appState.metricsSnapshot, decisions: appState.revenueDecisions)
                    .toolbar { RefreshToolbar() }
            case .personas:
                PersonasView()
            case .tasks:
                TasksView()
            case .chat:
                ChatCallsView()
            case .artifacts:
                ArtifactsView()
            case .settings:
                SettingsView()
            }
        }
    }
}

private struct RefreshToolbar: ToolbarContent {
    @EnvironmentObject private var appState: AppState

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                appState.refreshMetrics()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }
}

struct SidebarView: View {
    @Binding var selection: AppSection

    var body: some View {
        List(selection: $selection) {
            ForEach(AppSection.allCases) { section in
                Text(section.label)
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
    }
}

struct DashboardView: View {
    let metrics: RevenueSnapshot
    let decisions: [RevenueDecision]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("AgentDesk Dashboard")
                    .font(.largeTitle)
                MetricsGrid(metrics: metrics)
                if !decisions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Decisions")
                            .font(.title3)
                        ForEach(decisions) { decision in
                            DecisionCard(decision: decision)
                        }
                    }
                } else {
                    Text("No threshold decisions in the past cycle.")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
}

private struct MetricsGrid: View {
    let metrics: RevenueSnapshot

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
            MetricCard(title: "Jobs / Day", value: String(format: "%.1f", metrics.jobsPerDay), systemImage: "briefcase")
            MetricCard(title: "First Pass Yield", value: "\(Int(metrics.firstPassYield * 100))%", systemImage: "checkmark.seal")
            MetricCard(title: "SLA", value: "\(Int(metrics.sla * 100))%", systemImage: "clock")
            MetricCard(title: "EBITDA", value: String(format: "€%.2f", metrics.ebitda), systemImage: "eurosign.circle")
            MetricCard(title: "RPM", value: String(format: "€%.2f", metrics.rpm), systemImage: "speedometer")
            MetricCard(title: "Queue Depth", value: "\(metrics.queueDepth)", systemImage: "tray.full")
            MetricCard(title: "Accept Rate", value: "\(Int(metrics.acceptRate * 100))%", systemImage: "hand.thumbsup")
            MetricCard(title: "Avg Revision Cost", value: String(format: "€%.2f", metrics.avgRevisionCost), systemImage: "pencil.circle")
            MetricCard(title: "Token Cost / min", value: String(format: "€%.2f", metrics.tokenCostRate), systemImage: "number")
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(value)
                .font(.title2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

private struct DecisionCard: View {
    let decision: RevenueDecision

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(decision.trigger.rawValue.uppercased())
                    .font(.caption)
                    .bold()
                    .foregroundColor(.orange)
                Spacer()
                Text(decision.createdAt, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(decision.notes)
                .font(.body)
            if !decision.actions.isEmpty {
                HStack {
                    Image(systemName: "bolt")
                    Text(decision.actions.joined(separator: ", "))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.4)))
    }
}

struct PersonasView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showNewPersonaSheet = false
    @State private var draftPersona = Persona(name: "", role: "", tone: "", voicePreset: "alloy", voiceRate: 1.0, skills: [], toolsAllowed: [], ragCollections: [], constraints: [], samplePrompt: "")
    @State private var previewURL: URL?

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Personas")
                    .font(.largeTitle)
                Spacer()
                Button("New Persona") {
                    draftPersona = Persona(name: "", role: "", tone: "", voicePreset: "alloy", voiceRate: 1.0, skills: [], toolsAllowed: [], ragCollections: [], constraints: [], samplePrompt: "")
                    showNewPersonaSheet = true
                }
            }
            List(selection: $appState.selectedPersona) {
                ForEach(appState.personas) { persona in
                    VStack(alignment: .leading) {
                        HStack {
                            Text(persona.name)
                                .font(.headline)
                            Spacer()
                            Text(persona.role.capitalized)
                                .font(.subheadline)
                        }
                        Text(persona.tone)
                            .foregroundColor(.secondary)
                        HStack {
                            Label("Tools: \(persona.toolsAllowed.count)", systemImage: "wrench.and.screwdriver")
                            Label("RAG: \(persona.ragCollections.joined(separator: ", "))", systemImage: "books.vertical")
                        }
                        .font(.caption)
                    }
                    .tag(Optional(persona))
                }
            }
            if let selected = appState.selectedPersona {
                PersonaDetail(persona: selected, previewURL: $previewURL)
            } else {
                Text("Select a persona to view details.")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .sheet(isPresented: $showNewPersonaSheet) {
            PersonaEditor(persona: $draftPersona) { persona in
                appState.addPersona(persona)
                showNewPersonaSheet = false
            }
            .frame(width: 420, height: 520)
        }
    }
}

private struct PersonaDetail: View {
    let persona: Persona
    @Binding var previewURL: URL?
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voice preset: \(persona.voicePreset) @ \(String(format: "%.2f", persona.voiceRate))x")
            Text("Skills: \(persona.skills.joined(separator: ", "))")
            Text("Constraints: \(persona.constraints.joined(separator: ", "))")
            Button("Preview Voice") {
                previewURL = appState.previewVoice(for: persona)
            }
            if let preview = previewURL {
                Text("Generated preview at \(preview.path)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

private struct PersonaEditor: View {
    @Binding var persona: Persona
    var onSave: (Persona) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Persona")
                .font(.title2)
            TextField("Name", text: Binding(get: { persona.name }, set: { persona.name = $0 }))
            TextField("Role", text: Binding(get: { persona.role }, set: { persona.role = $0 }))
            TextField("Tone", text: Binding(get: { persona.tone }, set: { persona.tone = $0 }))
            TextField("Voice Preset", text: Binding(get: { persona.voicePreset }, set: { persona.voicePreset = $0 }))
            HStack {
                Text("Voice Rate")
                Slider(value: Binding(get: { persona.voiceRate }, set: { persona.voiceRate = $0 }), in: 0.8...1.3)
                Text(String(format: "%.2f", persona.voiceRate))
            }
            TextField("Sample Prompt", text: Binding(get: { persona.samplePrompt }, set: { persona.samplePrompt = $0 }))
            Button("Save") {
                var newPersona = persona
                newPersona.id = UUID()
                onSave(newPersona)
            }
            .disabled(persona.name.isEmpty || persona.role.isEmpty)
            Spacer()
        }
        .padding()
    }
}

struct TasksView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(TaskStage.allCases) { stage in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(stage.displayName)
                            .font(.title3)
                        ForEach(appState.tasks(in: stage)) { task in
                            TaskCard(task: task)
                        }
                    }
                    .frame(width: 280)
                }
            }
            .padding()
        }
    }
}

private struct TaskCard: View {
    @EnvironmentObject private var appState: AppState
    let task: Task

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.headline)
            Text(task.brief)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Budget: \(task.budgetMinutes) min · Client: \(task.client)")
                .font(.caption)
            HStack {
                Label("Tokens ~\(task.tokenEstimate)", systemImage: "textformat")
                Spacer()
                Label("Rev: \(task.revisionCount)", systemImage: "arrow.triangle.2.circlepath")
            }
            .font(.caption)
            Button("Advance") {
                appState.advance(task: task)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct ChatCallsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTaskID: UUID?
    @State private var composerText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Task", selection: Binding(get: {
                selectedTaskID ?? appState.tasks.first?.id
            }, set: { newID in
                selectedTaskID = newID
            })) {
                ForEach(appState.tasks) { task in
                    Text(task.title).tag(Optional(task.id))
                }
            }
            .pickerStyle(.segmented)

            if let task = currentTask {
                List {
                    ForEach(appState.messages(for: task)) { message in
                        VStack(alignment: .leading) {
                            Text(message.role.rawValue.capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(message.content)
                        }
                    }
                }
                HStack {
                    TextField("New message", text: $composerText, axis: .vertical)
                    Button("Send") {
                        appState.send(message: composerText, role: .manager, for: task)
                        composerText = ""
                    }
                    .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Button("Simulate Call Recording") {
                    _ = appState.simulateCall(for: task, persona: appState.personas.first)
                }
                .buttonStyle(.bordered)

                if !appState.recordings(for: task).isEmpty {
                    VStack(alignment: .leading) {
                        Text("Recordings")
                            .font(.headline)
                        ForEach(appState.recordings(for: task)) { record in
                            HStack {
                                Text(record.startedAt, style: .time)
                                Text(String(format: "%.0f sec", record.duration))
                                Spacer()
                                Text(record.recordingURL.lastPathComponent)
                            }
                            .font(.caption)
                        }
                    }
                }
            } else {
                Text("No tasks available.")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private var currentTask: Task? {
        if let id = selectedTaskID, let task = appState.tasks.first(where: { $0.id == id }) {
            return task
        }
        return appState.tasks.first
    }
}

struct ArtifactsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query: String = ""
    @State private var selectedCollections: String = ""
    @State private var retrievalResults: [RAGChunk] = []
    @State private var exportMessages: [UUID: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Artifacts & RAG")
                .font(.largeTitle)
            List {
                ForEach(appState.artifacts) { artifact in
                    DisclosureGroup(artifact.title) {
                        Text(artifact.latestVersionSummary)
                        ForEach(artifact.versions) { version in
                            HStack {
                                Text(version.summary)
                                Spacer()
                                Text(version.fileName)
                            }
                            .font(.caption)
                        }
                        Button("Export ZIP") {
                            if let task = appState.tasks.first(where: { $0.id == artifact.taskID }),
                               let url = appState.exportDelivery(for: task) {
                                exportMessages[artifact.id] = url.lastPathComponent
                            }
                        }
                        .buttonStyle(.bordered)
                        if let message = exportMessages[artifact.id] {
                            Text("Exported: \(message)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Retrieve from RAG")
                    .font(.headline)
                TextField("Query", text: $query)
                TextField("Collections (comma separated)", text: $selectedCollections)
                Button("Retrieve") {
                    let collections = selectedCollections.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    retrievalResults = appState.retrieveDocuments(query: query, collections: collections)
                }
                if !retrievalResults.isEmpty {
                    ForEach(retrievalResults, id: \.id) { chunk in
                        VStack(alignment: .leading) {
                            Text(String(format: "%.2f", chunk.score))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(chunk.text)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                    }
                }
            }
        }
        .padding()
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var localSettings: AppSettings = AppSettings()
    @State private var importPaths: String = ""
    @State private var importCollection: String = "default"
    @State private var complianceText: String = ""
    @State private var sanitizeHTML: String = "<p>Hello</p>"
    @State private var sanitizeResult: (String, [String]) = ("", [])

    var body: some View {
        Form {
            Section("Keys & Limits") {
                TextField("OpenAI Key Ref", text: Binding(get: { localSettings.openAIKeyReference }, set: { localSettings.openAIKeyReference = $0 }))
                Picker("Sourcing Mode", selection: Binding(get: { localSettings.sourcingMode }, set: { localSettings.sourcingMode = $0 })) {
                    Text("Dry-run").tag(AppSettings.SourcingMode.dryRun)
                    Text("Live").tag(AppSettings.SourcingMode.live)
                }
                Stepper("Token Limit/min: \(localSettings.tokenLimitPerMinute)", value: Binding(get: { localSettings.tokenLimitPerMinute }, set: { localSettings.tokenLimitPerMinute = $0 }), in: 1000...6000, step: 500)
                Toggle("Auto Bid Enabled", isOn: Binding(get: { localSettings.autoBidEnabled }, set: { localSettings.autoBidEnabled = $0 }))
                Button("Save Settings") {
                    appState.update(settings: localSettings)
                }
            }

            Section("RAG Import") {
                TextField("Paths (comma separated)", text: $importPaths)
                TextField("Collection", text: $importCollection)
                Button("Index") {
                    let paths = importPaths.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    appState.indexDocuments(paths: paths, collection: importCollection)
                }
                ForEach(Array(appState.ragCollections.keys).sorted(), id: \.self) { key in
                    if let stats = appState.ragCollections[key] {
                        Text("\(key): \(stats.files) files / \(stats.chunks) chunks")
                            .font(.caption)
                    }
                }
            }

            Section("Compliance") {
                TextField("Scan text", text: $complianceText, axis: .vertical)
                Button("Run Scan") {
                    appState.runComplianceScan(text: complianceText)
                }
                if let report = appState.lastComplianceReport {
                    Text("Verdict: \(report.verdict) — Flags: \(report.flags.joined(separator: ", "))")
                        .font(.caption)
                }
                TextField("HTML", text: $sanitizeHTML, axis: .vertical)
                Button("Sanitize HTML") {
                    sanitizeResult = appState.sanitize(html: sanitizeHTML)
                }
                if !sanitizeResult.0.isEmpty {
                    Text("Clean: \(sanitizeResult.0)")
                        .font(.caption)
                }
            }

            Section("Payments") {
                Button("Issue Invoice for First Task") {
                    if let firstTask = appState.tasks.first {
                        appState.issueInvoice(for: firstTask)
                    }
                }
                if let invoice = appState.lastInvoice {
                    Text("Invoice \(invoice.id) — Status: \(invoice.status.rawValue)")
                    Button("Mark Paid (simulate)") {
                        appState.settleInvoice()
                    }
                    ForEach(appState.lastInvoiceEvents, id: \.id) { event in
                        Text("Event: \(event.status.rawValue) @ \(event.createdAt)")
                            .font(.caption)
                    }
                }
            }
        }
        .padding()
        .onAppear {
            localSettings = appState.settings
        }
    }
}

struct AgentDeskApp_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState())
    }
}
