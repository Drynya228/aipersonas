import Foundation
import AgentCore

public struct CallRecord: Codable, Equatable, Identifiable {
    public var id: UUID
    public var taskID: UUID
    public var personaID: UUID?
    public var startedAt: Date
    public var endedAt: Date
    public var duration: TimeInterval
    public var transcript: String
    public var recordingURL: URL

    public init(id: UUID = UUID(),
                taskID: UUID,
                personaID: UUID?,
                startedAt: Date = .init(),
                endedAt: Date,
                duration: TimeInterval,
                transcript: String,
                recordingURL: URL) {
        self.id = id
        self.taskID = taskID
        self.personaID = personaID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.transcript = transcript
        self.recordingURL = recordingURL
    }
}

public final class VoiceService {
    private struct ActiveCall {
        let id: UUID
        let taskID: UUID
        let personaID: UUID?
        let startedAt: Date
    }

    private var activeCalls: [UUID: ActiveCall] = [:]
    private var completed: [CallRecord] = []
    private let lock = NSLock()

    public init() {}

    public func startCall(for taskID: UUID, personaID: UUID?) -> UUID {
        let call = ActiveCall(id: UUID(), taskID: taskID, personaID: personaID, startedAt: Date())
        lock.lock()
        activeCalls[call.id] = call
        lock.unlock()
        return call.id
    }

    @discardableResult
    public func endCall(callID: UUID, transcript: String) -> CallRecord? {
        lock.lock()
        defer { lock.unlock() }
        guard let active = activeCalls.removeValue(forKey: callID) else { return nil }
        let endedAt = Date()
        let duration = endedAt.timeIntervalSince(active.startedAt)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("call-\(callID).wav")
        let record = CallRecord(taskID: active.taskID,
                                personaID: active.personaID,
                                startedAt: active.startedAt,
                                endedAt: endedAt,
                                duration: duration,
                                transcript: transcript,
                                recordingURL: url)
        completed.append(record)
        return record
    }

    public func recordings(for taskID: UUID) -> [CallRecord] {
        lock.lock()
        defer { lock.unlock() }
        return completed.filter { $0.taskID == taskID }
    }

    public func previewSpeech(for persona: Persona, text: String) -> URL {
        let safeName = persona.name.replacingOccurrences(of: " ", with: "_").lowercased()
        let file = "tts-preview-\(safeName)-\(Int(persona.voiceRate * 100)).wav"
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(file)
    }
}
