import Foundation
import PhoneHubCore

enum CommunityShareError: LocalizedError, Equatable {
    case ghSetupRequired
    case duplicatePreset
    case invalidRequest(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .ghSetupRequired:
            return "GitHub CLI is required and must be authenticated. Run: brew install gh && gh auth login"
        case .duplicatePreset:
            return "a community preset with this name already exists for this app; rename it"
        case let .invalidRequest(message):
            return message
        case let .commandFailed(message):
            return message
        }
    }
}

@MainActor
final class CommunityShareController {
    typealias Runner = @Sendable (_ executablePath: String, _ arguments: [String]) throws -> CommandResult

    private let ghPath: String?
    private let runner: Runner

    init(
        ghPath: String? = resolveTool("gh"),
        runner: Runner? = nil
    ) {
        self.ghPath = ghPath
        self.runner = runner ?? { path, arguments in
            try runToolAt(path: path, args: arguments, timeout: 60)
        }
    }

    func submit(
        json: Data,
        path: String,
        name: String,
        platform: Platform,
        app: String
    ) async throws -> URL {
        guard let ghPath else { throw CommunityShareError.ghSetupRequired }
        let request = try CommunityShareRequest(
            json: json,
            path: path,
            name: name,
            platform: platform,
            app: app
        )
        let runner = runner
        return try await Task.detached(priority: .userInitiated) {
            try CommunityShareWorkflow(executablePath: ghPath, runner: runner).submit(request)
        }.value
    }
}

private struct CommunityShareRequest: Sendable {
    let json: Data
    let path: String
    let name: String
    let platform: Platform
    let app: String

    init(json: Data, path: String, name: String, platform: Platform, app: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CommunityShareError.invalidRequest("Preset name is required.")
        }
        guard !app.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CommunityShareError.invalidRequest("App name is required.")
        }
        let allowedPath = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-./")
        guard path.hasPrefix("presets/\(platform.rawValue)/"),
              path.hasSuffix(".json"),
              !path.contains(".."),
              path.unicodeScalars.allSatisfy(allowedPath.contains) else {
            throw CommunityShareError.invalidRequest("The community preset path is invalid.")
        }
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let steps = root["steps"] as? [Any],
              !steps.isEmpty else {
            throw CommunityShareError.invalidRequest("At least one step is required.")
        }
        self.json = json
        self.path = path
        self.name = name
        self.platform = platform
        self.app = app
    }
}

private struct CommunityShareWorkflow: Sendable {
    private static let upstream = "benasbarciauskas/phonehub-presets"
    let executablePath: String
    let runner: CommunityShareController.Runner

    func submit(_ request: CommunityShareRequest) throws -> URL {
        let auth = try run(["auth", "status"])
        guard auth.exitCode == 0 else { throw CommunityShareError.ghSetupRequired }

        let login = try output(
            ["api", "user", "-q", ".login"],
            context: "determining your GitHub login"
        )
        guard validGitHubLogin(login) else {
            throw CommunityShareError.commandFailed("GitHub CLI returned an invalid account login.")
        }

        try rejectExistingPath(request.path)

        let owner = login.lowercased()
        let target = owner == "benasbarciauskas" ? Self.upstream : "\(login)/phonehub-presets"
        if owner != "benasbarciauskas" {
            try ensureFork(target: target)
        }

        let defaultBranch = try output(
            ["api", "/repos/\(target)", "--jq", ".default_branch"],
            context: "reading the target repository"
        )
        guard validRefName(defaultBranch) else {
            throw CommunityShareError.commandFailed("The target repository has an invalid default branch.")
        }
        let headSHA = try output(
            ["api", "/repos/\(target)/git/ref/heads/\(defaultBranch)", "--jq", ".object.sha"],
            context: "reading the target branch"
        )
        guard headSHA.count == 40,
              headSHA.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) else {
            throw CommunityShareError.commandFailed("GitHub CLI returned an invalid branch revision.")
        }

        let branch = branchName(app: request.app, name: request.name)
        try requireSuccess(
            [
                "api", "-X", "POST", "/repos/\(target)/git/refs",
                "-f", "ref=refs/heads/\(branch)",
                "-f", "sha=\(headSHA)",
            ],
            context: "creating the contribution branch"
        )
        try requireSuccess(
            [
                "api", "-X", "PUT", "/repos/\(target)/contents/\(request.path)",
                "-f", "message=preset: \(request.name)",
                "-f", "content=\(request.json.base64EncodedString())",
                "-f", "branch=\(branch)",
            ],
            context: "uploading the community preset"
        )

        let title = "preset: \(request.name) (\(request.platform.rawValue)/\(request.app))"
        let urlString = try output(
            [
                "api", "-X", "POST", "/repos/\(Self.upstream)/pulls",
                "-f", "title=\(title)",
                "-f", "head=\(login):\(branch)",
                "-f", "base=main",
                "-f", "body=Submitted from PhoneHub.",
                "--jq", ".html_url",
            ],
            context: "opening the pull request"
        )
        guard let url = URL(string: urlString),
              url.scheme == "https",
              url.host == "github.com" else {
            throw CommunityShareError.commandFailed("GitHub CLI returned an invalid pull request URL.")
        }
        return url
    }

    private func rejectExistingPath(_ path: String) throws {
        let result = try run([
            "api", "/repos/\(Self.upstream)/contents/\(path)?ref=main", "--silent",
        ])
        if result.exitCode == 0 { throw CommunityShareError.duplicatePreset }
        guard result.stderr.contains("404") else {
            throw commandError(result, context: "checking for an existing community preset")
        }
    }

    private func ensureFork(target: String) throws {
        let fork = try run(["repo", "fork", Self.upstream, "--clone=false"])
        guard fork.exitCode == 0 else {
            let existing = try run(["api", "/repos/\(target)", "--silent"])
            guard existing.exitCode == 0 else {
                throw commandError(fork, context: "creating your phonehub-presets fork")
            }
            return
        }
    }

    private func output(_ arguments: [String], context: String) throws -> String {
        let result = try run(arguments)
        guard result.exitCode == 0 else { throw commandError(result, context: context) }
        let value = String(decoding: result.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw CommunityShareError.commandFailed("GitHub CLI returned no result while \(context).")
        }
        return value
    }

    private func requireSuccess(_ arguments: [String], context: String) throws {
        let result = try run(arguments)
        guard result.exitCode == 0 else { throw commandError(result, context: context) }
    }

    private func run(_ arguments: [String]) throws -> CommandResult {
        do {
            return try runner(executablePath, arguments)
        } catch {
            throw CommunityShareError.commandFailed("GitHub CLI could not run: \(error.localizedDescription)")
        }
    }

    private func commandError(_ result: CommandResult, context: String) -> CommunityShareError {
        let detail = result.stderr
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let suffix = detail.isEmpty ? "" : ": \(detail.prefix(300))"
        return .commandFailed("GitHub CLI failed while \(context)\(suffix)")
    }

    private func branchName(app: String, name: String) -> String {
        let appPart = slug(app).prefix(32)
        let namePart = slug(name).prefix(48)
        let unique = UUID().uuidString.lowercased().prefix(8)
        return "community/\(appPart)-\(namePart)-\(unique)"
    }

    private func validGitHubLogin(_ login: String) -> Bool {
        guard (1...39).contains(login.count), login.first != "-", login.last != "-" else {
            return false
        }
        return login.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "-"
        }
    }

    private func validRefName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.hasSuffix("/"), !name.contains("..") else {
            return false
        }
        let forbidden = CharacterSet(charactersIn: " ~^:?*[\\")
            .union(.controlCharacters)
        return name.unicodeScalars.allSatisfy { !forbidden.contains($0) }
    }
}
