import Foundation
import XCTest
@testable import PhoneHub
@testable import PhoneHubCore

@MainActor
final class CommunityShareControllerTests: XCTestCase {
    private let json = Data(#"{"name":"Open Instagram","steps":[{"type":"pressHome"}]}"#.utf8)
    private let path = "presets/ios/instagram/open-instagram.json"

    func testNonOwnerForksUploadsWithArgvAndOpensUpstreamPR() async throws {
        let recorder = GHRecorder(login: "octocat")
        let controller = CommunityShareController(ghPath: "/fake/gh", runner: runner(for: recorder))

        let url = try await controller.submit(
            json: json,
            path: path,
            name: "Open Instagram",
            platform: .ios,
            app: "Instagram"
        )

        XCTAssertEqual(url.absoluteString, "https://github.com/benasbarciauskas/phonehub-presets/pull/42")
        let calls = recorder.calls
        XCTAssertTrue(calls.contains(["repo", "fork", "benasbarciauskas/phonehub-presets", "--clone=false"]))
        let createRef = try XCTUnwrap(calls.first { $0.contains("/repos/octocat/phonehub-presets/git/refs") })
        XCTAssertTrue(try XCTUnwrap(fieldValue("ref", in: createRef)).hasPrefix("refs/heads/community/"))
        XCTAssertTrue(createRef.contains("sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))

        let upload = try XCTUnwrap(calls.first { $0.contains("/repos/octocat/phonehub-presets/contents/\(path)") && $0.contains("PUT") })
        XCTAssertTrue(upload.contains("message=preset: Open Instagram"))
        XCTAssertTrue(upload.contains("content=\(json.base64EncodedString())"))
        XCTAssertNotNil(fieldValue("branch", in: upload))

        let pull = try XCTUnwrap(calls.first { $0.contains("/repos/benasbarciauskas/phonehub-presets/pulls") })
        XCTAssertTrue(pull.contains("title=preset: Open Instagram (ios/Instagram)"))
        XCTAssertTrue(pull.contains(where: { $0.hasPrefix("head=octocat:community/") }))
        XCTAssertTrue(pull.contains("base=main"))
        XCTAssertFalse(calls.flatMap { $0 }.contains(where: { $0 == "sh" || $0 == "-c" }))
    }

    func testOwnerTargetsUpstreamWithoutFork() async throws {
        let recorder = GHRecorder(login: "benasbarciauskas")
        let controller = CommunityShareController(ghPath: "/fake/gh", runner: runner(for: recorder))

        _ = try await controller.submit(
            json: json, path: path, name: "Open Instagram", platform: .ios, app: "Instagram"
        )

        XCTAssertFalse(recorder.calls.contains(where: { $0.starts(with: ["repo", "fork"]) }))
        XCTAssertTrue(recorder.calls.contains(where: {
            $0.contains("/repos/benasbarciauskas/phonehub-presets/contents/\(path)")
        }))
    }

    func testExistingUpstreamPathReturnsRenameErrorBeforeMutation() async {
        let recorder = GHRecorder(login: "octocat", pathExists: true)
        let controller = CommunityShareController(ghPath: "/fake/gh", runner: runner(for: recorder))

        do {
            _ = try await controller.submit(
                json: json, path: path, name: "Open Instagram", platform: .ios, app: "Instagram"
            )
            XCTFail("Expected duplicate error")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "a community preset with this name already exists for this app; rename it"
            )
        }
        XCTAssertFalse(recorder.calls.contains(where: { $0.first == "repo" }))
        XCTAssertFalse(recorder.calls.contains(where: { $0.contains("PUT") }))
    }

    func testMissingOrUnauthedGHSuggestsInstallAndLogin() async {
        let missing = GHRecorder(login: "octocat")
        let missingController = CommunityShareController(ghPath: nil, runner: runner(for: missing))
        await assertGHSetupError(from: missingController)
        XCTAssertTrue(missing.calls.isEmpty)

        let unauthed = GHRecorder(login: "octocat", authenticated: false)
        let unauthedController = CommunityShareController(
            ghPath: "/fake/gh",
            runner: runner(for: unauthed)
        )
        await assertGHSetupError(from: unauthedController)
    }

    private func assertGHSetupError(from controller: CommunityShareController) async {
        do {
            _ = try await controller.submit(
                json: json, path: path, name: "Open Instagram", platform: .ios, app: "Instagram"
            )
            XCTFail("Expected gh setup error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("brew install gh && gh auth login"))
        }
    }

    private func fieldValue(_ name: String, in args: [String]) -> String? {
        args.first(where: { $0.hasPrefix("\(name)=") })?.dropFirst(name.count + 1).description
    }

    private func runner(for recorder: GHRecorder) -> CommunityShareController.Runner {
        { @Sendable path, arguments in
            try recorder.run(path, arguments)
        }
    }
}

private final class GHRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    private let login: String
    private let authenticated: Bool
    private let pathExists: Bool

    init(login: String, authenticated: Bool = true, pathExists: Bool = false) {
        self.login = login
        self.authenticated = authenticated
        self.pathExists = pathExists
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func run(_ path: String, _ args: [String]) throws -> CommandResult {
        XCTAssertEqual(path, "/fake/gh")
        lock.lock()
        recorded.append(args)
        lock.unlock()

        if args == ["auth", "status"] {
            return result(authenticated ? 0 : 1, stderr: authenticated ? "" : "not logged in")
        }
        if args == ["api", "user", "-q", ".login"] { return result(0, stdout: login) }
        if args.count > 1, args[0] == "api", args[1].contains("/contents/") {
            return pathExists ? result(0, stdout: "{}") : result(1, stderr: "gh: Not Found (HTTP 404)")
        }
        if args == ["repo", "fork", "benasbarciauskas/phonehub-presets", "--clone=false"] {
            return result(0)
        }
        if args.count > 1, args[0] == "api", args[1].hasSuffix("/phonehub-presets"),
           args.suffix(2) == ["--jq", ".default_branch"] {
            return result(0, stdout: "main")
        }
        if args.count > 1, args[0] == "api", args[1].contains("/git/ref/heads/") {
            return result(0, stdout: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        }
        if args.contains("/repos/benasbarciauskas/phonehub-presets/pulls") {
            return result(0, stdout: "https://github.com/benasbarciauskas/phonehub-presets/pull/42")
        }
        return result(0)
    }

    private func result(_ exitCode: Int32, stdout: String = "", stderr: String = "") -> CommandResult {
        CommandResult(exitCode: exitCode, stdout: Data(stdout.utf8), stderr: stderr)
    }
}
