import Foundation
import PhoneHubCore

/// In-flight preset run identity used to write one history row on terminal state.
struct RunHistoryContext {
    let name: String
    let deviceId: String
    let deviceName: String
    let startedAt: Date
}

@MainActor
extension AutomationEngine {
    func beginHistory(name: String, device: Device) {
        historyContext = RunHistoryContext(
            name: name,
            deviceId: device.id,
            deviceName: device.model,
            startedAt: .now
        )
    }

    /// Append one history record for the active run (once). Safe no-op if already recorded or no store.
    func recordHistory(_ outcome: RunOutcome) {
        guard let ctx = historyContext else { return }
        historyContext = nil
        guard let store = runHistoryStore else { return }
        store.append(
            RunRecord(
                name: ctx.name,
                kind: .preset,
                deviceId: ctx.deviceId,
                deviceName: ctx.deviceName,
                startedAt: ctx.startedAt,
                endedAt: .now,
                outcome: outcome,
                log: log
            ),
            deviceId: ctx.deviceId
        )
    }
}
