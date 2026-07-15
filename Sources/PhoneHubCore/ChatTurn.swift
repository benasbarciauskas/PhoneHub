public enum ChatTurn {
    public static func sessionId(
        _ sessionId: String?,
        storedBackend: AgentBackend,
        selectedBackend: AgentBackend
    ) -> String? {
        storedBackend == selectedBackend ? sessionId : nil
    }

    public static func shouldRetryAsFresh(
        exitCode: Int32,
        isResumeTurn: Bool,
        alreadyRetried: Bool
    ) -> Bool {
        exitCode != 0 && isResumeTurn && !alreadyRetried
    }
}
