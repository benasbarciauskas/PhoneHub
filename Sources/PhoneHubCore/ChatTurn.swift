public enum ChatTurn {
    public static func shouldRetryAsFresh(
        exitCode: Int32,
        isResumeTurn: Bool,
        alreadyRetried: Bool
    ) -> Bool {
        exitCode != 0 && isResumeTurn && !alreadyRetried
    }
}
