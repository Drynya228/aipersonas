import Foundation

public struct Persona: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var role: String
    public var tone: String
    public var voicePreset: String
    public var voiceRate: Double
    public var skills: [String]
    public var toolsAllowed: [String]
    public var ragCollections: [String]
    public var constraints: [String]
    public var samplePrompt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case role
        case tone
        case voicePreset
        case voiceRate
        case skills
        case toolsAllowed = "tools_allowed"
        case ragCollections = "rag_collections"
        case constraints
        case samplePrompt = "sample_prompt"
    }

    public init(id: UUID = UUID(),
                name: String,
                role: String,
                tone: String,
                voicePreset: String,
                voiceRate: Double,
                skills: [String],
                toolsAllowed: [String],
                ragCollections: [String],
                constraints: [String],
                samplePrompt: String = "") {
        self.id = id
        self.name = name
        self.role = role
        self.tone = tone
        self.voicePreset = voicePreset
        self.voiceRate = voiceRate
        self.skills = skills
        self.toolsAllowed = toolsAllowed
        self.ragCollections = ragCollections
        self.constraints = constraints
        self.samplePrompt = samplePrompt
    }
}

public enum TaskStage: String, Codable, CaseIterable, Identifiable {
    case intake
    case inProgress
    case validate
    case deliver

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .intake: return "Intake"
        case .inProgress: return "In Progress"
        case .validate: return "Validate"
        case .deliver: return "Deliver"
        }
    }

    public var limitMinutes: Int {
        switch self {
        case .intake: return 30
        case .inProgress: return 90
        case .validate: return 45
        case .deliver: return 30
        }
    }
}

public struct Task: Codable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var brief: String
    public var stage: TaskStage
    public var createdAt: Date
    public var updatedAt: Date
    public var dueDate: Date
    public var personaAssignments: [UUID]
    public var budgetMinutes: Int
    public var client: String
    public var tags: [String]
    public var checklist: String
    public var revisionCount: Int
    public var tokenEstimate: Int

    public init(id: UUID = UUID(),
                title: String,
                brief: String,
                stage: TaskStage,
                createdAt: Date = .init(),
                updatedAt: Date = .init(),
                dueDate: Date,
                personaAssignments: [UUID],
                budgetMinutes: Int,
                client: String,
                tags: [String],
                checklist: String,
                revisionCount: Int = 0,
                tokenEstimate: Int = 0) {
        self.id = id
        self.title = title
        self.brief = brief
        self.stage = stage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dueDate = dueDate
        self.personaAssignments = personaAssignments
        self.budgetMinutes = budgetMinutes
        self.client = client
        self.tags = tags
        self.checklist = checklist
        self.revisionCount = revisionCount
        self.tokenEstimate = tokenEstimate
    }
}

public struct ArtifactVersion: Codable, Identifiable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var authorPersonaID: UUID?
    public var summary: String
    public var fileName: String
    public var size: Int

    public init(id: UUID = UUID(),
                createdAt: Date = .init(),
                authorPersonaID: UUID? = nil,
                summary: String,
                fileName: String,
                size: Int) {
        self.id = id
        self.createdAt = createdAt
        self.authorPersonaID = authorPersonaID
        self.summary = summary
        self.fileName = fileName
        self.size = size
    }
}

public struct Artifact: Codable, Identifiable, Equatable {
    public var id: UUID
    public var taskID: UUID
    public var title: String
    public var latestVersionSummary: String
    public var versions: [ArtifactVersion]

    public init(id: UUID = UUID(),
                taskID: UUID,
                title: String,
                latestVersionSummary: String,
                versions: [ArtifactVersion]) {
        self.id = id
        self.taskID = taskID
        self.title = title
        self.latestVersionSummary = latestVersionSummary
        self.versions = versions
    }
}

public struct AppSettings: Codable, Equatable {
    public enum SourcingMode: String, Codable {
        case dryRun
        case live
    }

    public var openAIKeyReference: String
    public var paymentsKeyReference: String
    public var sourcingMode: SourcingMode
    public var tokenLimitPerMinute: Int
    public var audioMinuteLimitPerDay: Int
    public var autoBidEnabled: Bool
    public var complianceFreezeReason: String?

    public init(openAIKeyReference: String = "keychain://openai",
                paymentsKeyReference: String = "keychain://payments",
                sourcingMode: SourcingMode = .dryRun,
                tokenLimitPerMinute: Int = 3500,
                audioMinuteLimitPerDay: Int = 30,
                autoBidEnabled: Bool = true,
                complianceFreezeReason: String? = nil) {
        self.openAIKeyReference = openAIKeyReference
        self.paymentsKeyReference = paymentsKeyReference
        self.sourcingMode = sourcingMode
        self.tokenLimitPerMinute = tokenLimitPerMinute
        self.audioMinuteLimitPerDay = audioMinuteLimitPerDay
        self.autoBidEnabled = autoBidEnabled
        self.complianceFreezeReason = complianceFreezeReason
    }
}

public struct RevenueSnapshot: Equatable {
    public enum Window {
        case oneDay
        case sevenDay
    }

    public var jobsPerDay: Double
    public var firstPassYield: Double
    public var sla: Double
    public var ebitda: Double
    public var queueDepth: Int
    public var tokenCostRate: Double
    public var rpm: Double
    public var acceptRate: Double
    public var avgRevisionCost: Double
    public var audioMinutes: Double

    public static let placeholder = RevenueSnapshot(jobsPerDay: 2.2,
                                                    firstPassYield: 0.74,
                                                    sla: 0.95,
                                                    ebitda: 22.4,
                                                    queueDepth: 5,
                                                    tokenCostRate: 0.21,
                                                    rpm: 7.2,
                                                    acceptRate: 0.71,
                                                    avgRevisionCost: 2.8,
                                                    audioMinutes: 14)

    public init(jobsPerDay: Double,
                firstPassYield: Double,
                sla: Double,
                ebitda: Double,
                queueDepth: Int,
                tokenCostRate: Double,
                rpm: Double,
                acceptRate: Double,
                avgRevisionCost: Double,
                audioMinutes: Double) {
        self.jobsPerDay = jobsPerDay
        self.firstPassYield = firstPassYield
        self.sla = sla
        self.ebitda = ebitda
        self.queueDepth = queueDepth
        self.tokenCostRate = tokenCostRate
        self.rpm = rpm
        self.acceptRate = acceptRate
        self.avgRevisionCost = avgRevisionCost
        self.audioMinutes = audioMinutes
    }
}

public struct RevenueDecision: Codable, Equatable, Identifiable {
    public enum Trigger: String, Codable {
        case lowRPM
        case lowAcceptRate
        case highRevisionCost
    }

    public var id: UUID
    public var trigger: Trigger
    public var createdAt: Date
    public var notes: String
    public var actions: [String]

    public init(id: UUID = UUID(),
                trigger: Trigger,
                createdAt: Date = .init(),
                notes: String,
                actions: [String] = []) {
        self.id = id
        self.trigger = trigger
        self.createdAt = createdAt
        self.notes = notes
        self.actions = actions
    }
}

public extension Task {
    static func sample(personaIDs: [UUID]) -> [Task] {
        let now = Date()
        return [
            Task(title: "EN→RU Landing Page",
                 brief: "Localize hero, features, and CTA for fintech landing page with compliance tone.",
                 stage: .inProgress,
                 createdAt: now.addingTimeInterval(-3600),
                 updatedAt: now.addingTimeInterval(-1200),
                 dueDate: now.addingTimeInterval(7200),
                 personaAssignments: Array(personaIDs.prefix(2)),
                 budgetMinutes: 80,
                 client: "Acme Fintech",
                 tags: ["translate", "fintech"],
                 checklist: "Docs/checklists/translate.yml",
                 revisionCount: 0,
                 tokenEstimate: 4200),
            Task(title: "Validator QA",
                 brief: "Apply translate checklist and ensure CTA matches localized voice.",
                 stage: .validate,
                 createdAt: now.addingTimeInterval(-7200),
                 updatedAt: now.addingTimeInterval(-1800),
                 dueDate: now.addingTimeInterval(5400),
                 personaAssignments: Array(personaIDs.suffix(1)),
                 budgetMinutes: 45,
                 client: "Acme Fintech",
                 tags: ["qa", "validator"],
                 checklist: "Docs/checklists/translate.yml",
                 revisionCount: 1,
                 tokenEstimate: 800),
            Task(title: "Prospecting new AI leads",
                 brief: "Search for translation gigs with high acceptance probability and prepare bid drafts.",
                 stage: .intake,
                 createdAt: now.addingTimeInterval(-10800),
                 updatedAt: now.addingTimeInterval(-10800),
                 dueDate: now.addingTimeInterval(14400),
                 personaAssignments: Array(personaIDs.prefix(1)),
                 budgetMinutes: 60,
                 client: "Pipeline",
                 tags: ["sourcing"],
                 checklist: "Docs/checklists/text.yml",
                 revisionCount: 0,
                 tokenEstimate: 1100)
        ]
    }
}

public extension Artifact {
    static func sample(for task: Task) -> [Artifact] {
        [
            Artifact(taskID: task.id,
                     title: "Landing page draft",
                     latestVersionSummary: "Includes localized hero + pricing tiers.",
                     versions: [
                        ArtifactVersion(authorPersonaID: task.personaAssignments.first,
                                        summary: "Initial translation draft",
                                        fileName: "landing_v1.md",
                                        size: 14_200),
                        ArtifactVersion(authorPersonaID: task.personaAssignments.first,
                                        summary: "Applied validator edits",
                                        fileName: "landing_v2.md",
                                        size: 14_560)
                     ])
        ]
    }
}
