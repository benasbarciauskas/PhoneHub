import Foundation

public let automationSettleMilliseconds = 500

public func stepsToRun(automation: Automation) -> [AutomationStep] {
    if !automation.useCondensed, let rawSteps = automation.rawSteps { return rawSteps }
    return automation.steps
}

public func nextIteration(loop: LoopMode, current: Int) -> Int? {
    switch loop {
    case .once:
        return nil
    case .times(let count):
        let next = current + 1
        return count > 0 && next < count ? next : nil
    case .forever:
        return current + 1
    }
}
