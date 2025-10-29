import Foundation
import AgentCore

public final class RevenueMetricsService {
    private struct HistoricalSample {
        let timestamp: Date
        let snapshot: RevenueSnapshot
    }

    private var history: [HistoricalSample] = []
    private var decisionsLog: [RevenueDecision] = []
    private let queue = DispatchQueue(label: "ai.agentdesk.revenue", qos: .userInitiated)

    public init() {}

    @discardableResult
    public func record(snapshot: RevenueSnapshot, at date: Date = Date()) -> [RevenueDecision] {
        queue.sync {
            history.append(HistoricalSample(timestamp: date, snapshot: snapshot))
        }
        let decisions = evaluateThresholds(snapshot: snapshot, at: date)
        queue.sync {
            decisionsLog.append(contentsOf: decisions)
        }
        return decisions
    }

    public func snapshot(window: RevenueSnapshot.Window, now: Date = Date()) -> RevenueSnapshot {
        let windowSeconds: TimeInterval = window == .oneDay ? 86_400 : 604_800
        let filtered = queue.sync {
            history.filter { now.timeIntervalSince($0.timestamp) <= windowSeconds }
        }
        guard !filtered.isEmpty else {
            return window == .oneDay ? RevenueSnapshot.placeholder : RevenueSnapshot(jobsPerDay: 2.6,
                                                                                      firstPassYield: 0.76,
                                                                                      sla: 0.95,
                                                                                      ebitda: 24.8,
                                                                                      queueDepth: 6,
                                                                                      tokenCostRate: 0.2,
                                                                                      rpm: 7.0,
                                                                                      acceptRate: 0.69,
                                                                                      avgRevisionCost: 3.0,
                                                                                      audioMinutes: 18)
        }
        let aggregated = filtered.reduce((jobs: 0.0, fpy: 0.0, sla: 0.0, ebitda: 0.0, queue: 0, tcr: 0.0, rpm: 0.0, accept: 0.0, rev: 0.0, audio: 0.0)) { partial, sample in
            let snap = sample.snapshot
            return (partial.jobs + snap.jobsPerDay,
                    partial.fpy + snap.firstPassYield,
                    partial.sla + snap.sla,
                    partial.ebitda + snap.ebitda,
                    partial.queue + snap.queueDepth,
                    partial.tcr + snap.tokenCostRate,
                    partial.rpm + snap.rpm,
                    partial.accept + snap.acceptRate,
                    partial.rev + snap.avgRevisionCost,
                    partial.audio + snap.audioMinutes)
        }
        let count = Double(filtered.count)
        return RevenueSnapshot(jobsPerDay: aggregated.jobs / count,
                               firstPassYield: aggregated.fpy / count,
                               sla: aggregated.sla / count,
                               ebitda: aggregated.ebitda / count,
                               queueDepth: Int((Double(aggregated.queue) / count).rounded()),
                               tokenCostRate: aggregated.tcr / count,
                               rpm: aggregated.rpm / count,
                               acceptRate: aggregated.accept / count,
                               avgRevisionCost: aggregated.rev / count,
                               audioMinutes: aggregated.audio / count)
    }

    public func evaluateThresholds(snapshot: RevenueSnapshot, at date: Date = Date()) -> [RevenueDecision] {
        var decisions: [RevenueDecision] = []
        if snapshot.rpm < 6.0 && snapshot.queueDepth < 8 {
            decisions.append(RevenueDecision(trigger: .lowRPM,
                                             createdAt: date,
                                             notes: "RPM below profitability floor while queue is light.",
                                             actions: ["routing.rebalance", "market.search"]))
        }
        if snapshot.acceptRate < 0.35 {
            decisions.append(RevenueDecision(trigger: .lowAcceptRate,
                                             createdAt: date,
                                             notes: "Low acceptance rate detected.",
                                             actions: ["tighten-intake-filters", "reinforce-briefing"]))
        }
        if snapshot.avgRevisionCost > 4.0 {
            decisions.append(RevenueDecision(trigger: .highRevisionCost,
                                             createdAt: date,
                                             notes: "Average revision cost too high.",
                                             actions: ["increase-pricing", "strengthen-checklists"]))
        }
        return decisions
    }

    public func recentDecisions(limit: Int = 5) -> [RevenueDecision] {
        queue.sync {
            Array(decisionsLog.suffix(limit))
        }
    }
}
