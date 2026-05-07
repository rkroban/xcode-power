import Foundation

/// Actor that controls Xcode via JXA (JavaScript for Automation) scripting.
/// Conforms to `XcodeControlling` for dependency injection in tests.
actor XcodeController: XcodeControlling {

    /// The default timeout for non-build/test operations.
    static let defaultTimeout: Duration = .seconds(30)

    /// The injected process executor for running osascript commands.
    private let processExecutor: ProcessExecuting

    /// Creates an XcodeController with the given process executor.
    /// - Parameter processExecutor: The executor used to run osascript commands.
    init(processExecutor: ProcessExecuting = ProcessExecutor()) {
        self.processExecutor = processExecutor
    }

    // MARK: - XcodeControlling Protocol

    func isXcodeRunning() async throws -> Bool {
        let script = Self.jxaIsXcodeRunning()
        let output = try await executeJXA(script, timeout: Self.defaultTimeout)
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    func hasOpenProject() async throws -> Bool {
        let script = Self.jxaHasOpenProject()
        let output = try await executeJXA(script, timeout: Self.defaultTimeout)
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    func executeJXA(_ script: String, timeout: Duration) async throws -> String {
        let output = try await processExecutor.run(
            command: "/usr/bin/osascript",
            arguments: ["-l", "JavaScript", "-e", script],
            timeout: timeout
        )
        return output.stdout
    }

    // MARK: - Build, Test, Run, Schemes, Diagnostics, Clean

    /// Triggers a build for the given scheme (nil = active scheme).
    func build(scheme: String?) async throws -> String {
        try await ensureXcodeReady(requireProject: true)
        let script = Self.jxaBuild(scheme: scheme)
        return try await executeJXA(script, timeout: Self.defaultTimeout)
    }

    /// Triggers test execution for the given scheme and optional test identifier.
    func test(scheme: String?, testIdentifier: String?) async throws -> String {
        try await ensureXcodeReady(requireProject: true)
        let script = Self.jxaTest(scheme: scheme, testIdentifier: testIdentifier)
        return try await executeJXA(script, timeout: Self.defaultTimeout)
    }

    /// Triggers run action for the given scheme (nil = active scheme).
    func run(scheme: String?) async throws -> String {
        try await ensureXcodeReady(requireProject: true)
        let script = Self.jxaRun(scheme: scheme)
        return try await executeJXA(script, timeout: Self.defaultTimeout)
    }

    /// Lists all schemes in the active workspace/project.
    func listSchemes() async throws -> [SchemeInfo] {
        try await ensureXcodeReady(requireProject: false)
        let script = Self.jxaListSchemes()
        let output = try await executeJXA(script, timeout: Self.defaultTimeout)
        return parseSchemes(from: output)
    }

    /// Retrieves current build diagnostics.
    func getDiagnostics() async throws -> [Diagnostic] {
        try await ensureXcodeReady(requireProject: false)
        let script = Self.jxaGetDiagnostics()
        let output = try await executeJXA(script, timeout: Self.defaultTimeout)
        return parseDiagnostics(from: output)
    }

    /// Cleans the build folder for the given scheme (nil = active scheme).
    func clean(scheme: String?) async throws -> String {
        try await ensureXcodeReady(requireProject: false)
        let script = Self.jxaClean(scheme: scheme)
        return try await executeJXA(script, timeout: Self.defaultTimeout)
    }

    // MARK: - Private Helpers

    /// Ensures Xcode is running and optionally that a project is open.
    private func ensureXcodeReady(requireProject: Bool) async throws {
        guard try await isXcodeRunning() else {
            throw XcodePowerError.xcodeNotRunning
        }
        if requireProject {
            guard try await hasOpenProject() else {
                throw XcodePowerError.noProjectOpen
            }
        }
    }

    /// Parses scheme names from JXA JSON output.
    private func parseSchemes(from output: String) -> [SchemeInfo] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[]" else { return [] }
        guard let data = trimmed.data(using: .utf8),
              let names = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return names.map { SchemeInfo(name: $0) }
    }

    /// Parses diagnostics from JXA JSON output.
    private func parseDiagnostics(from output: String) -> [Diagnostic] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[]" else { return [] }
        guard let data = trimmed.data(using: .utf8),
              let diagnostics = try? JSONDecoder().decode([Diagnostic].self, from: data) else {
            return []
        }
        return diagnostics
    }

    // MARK: - JXA Script Generation (internal for testing)

    /// Generates JXA script to check if Xcode is running.
    static func jxaIsXcodeRunning() -> String {
        """
        var app = Application("System Events");
        var procs = app.processes.whose({name: "Xcode"});
        procs.length > 0 ? "true" : "false";
        """
    }

    /// Generates JXA script to check if Xcode has an open project/workspace.
    static func jxaHasOpenProject() -> String {
        """
        var xcode = Application("Xcode");
        xcode.workspaceDocuments().length > 0 ? "true" : "false";
        """
    }

    /// Generates JXA script to trigger a build action.
    /// The Xcode `build` command is asynchronous — it returns a scheme action result
    /// immediately. We poll actionResult.status() until it reaches a terminal state.
    /// - Parameter scheme: The scheme to build, or nil for the active scheme.
    static func jxaBuild(scheme: String?) -> String {
        if let scheme = scheme {
            return """
            var xcode = Application("Xcode");
            var workspace = xcode.workspaceDocuments[0];
            var schemeToUse = "\(escapeJXAString(scheme))";
            var actionResult = xcode.build(workspace, {scheme: schemeToUse});
            var status = actionResult.status();
            while (status === "not yet started" || status === "running") {
                delay(2);
                status = actionResult.status();
            }
            status;
            """
        } else {
            return """
            var xcode = Application("Xcode");
            var workspace = xcode.workspaceDocuments[0];
            var actionResult = xcode.build(workspace);
            var status = actionResult.status();
            while (status === "not yet started" || status === "running") {
                delay(2);
                status = actionResult.status();
            }
            status;
            """
        }
    }

    /// Generates JXA script to trigger a test action.
    /// - Parameters:
    ///   - scheme: The scheme to test, or nil for the active scheme.
    ///   - testIdentifier: Optional test class or method identifier.
    static func jxaTest(scheme: String?, testIdentifier: String?) -> String {
        var script = """
        var xcode = Application("Xcode");
        var workspace = xcode.workspaceDocuments[0];

        """

        if let scheme = scheme {
            script += """
            var schemeToUse = "\(escapeJXAString(scheme))";

            """
        }

        if let testIdentifier = testIdentifier {
            script += """
            var testId = "\(escapeJXAString(testIdentifier))";

            """
        }

        if scheme != nil && testIdentifier != nil {
            script += """
            xcode.test(workspace, {scheme: schemeToUse, testIdentifier: testId});
            "test triggered for scheme: " + schemeToUse + " test: " + testId;
            """
        } else if scheme != nil {
            script += """
            xcode.test(workspace, {scheme: schemeToUse});
            "test triggered for scheme: " + schemeToUse;
            """
        } else if testIdentifier != nil {
            script += """
            xcode.test(workspace, {testIdentifier: testId});
            "test triggered for test: " + testId;
            """
        } else {
            script += """
            xcode.test(workspace);
            "test triggered for active scheme";
            """
        }

        return script
    }

    /// Generates JXA script to trigger a run action.
    /// - Parameter scheme: The scheme to run, or nil for the active scheme.
    static func jxaRun(scheme: String?) -> String {
        if let scheme = scheme {
            return """
            var xcode = Application("Xcode");
            var workspace = xcode.workspaceDocuments[0];
            var schemeToUse = "\(escapeJXAString(scheme))";
            xcode.run(workspace, {scheme: schemeToUse});
            "run triggered for scheme: " + schemeToUse;
            """
        } else {
            return """
            var xcode = Application("Xcode");
            var workspace = xcode.workspaceDocuments[0];
            xcode.run(workspace);
            "run triggered for active scheme";
            """
        }
    }

    /// Generates JXA script to list all schemes in the active workspace.
    static func jxaListSchemes() -> String {
        """
        var xcode = Application("Xcode");
        var workspace = xcode.workspaceDocuments[0];
        var schemes = workspace.schemes();
        var names = [];
        for (var i = 0; i < schemes.length; i++) {
            names.push(schemes[i].name());
        }
        JSON.stringify(names);
        """
    }

    /// Generates JXA script to retrieve build diagnostics.
    static func jxaGetDiagnostics() -> String {
        """
        var xcode = Application("Xcode");
        var workspace = xcode.workspaceDocuments[0];
        var result = workspace.lastSchemeActionResult();
        var diagnostics = [];
        var errors = result.buildErrors();
        for (var i = 0; i < errors.length; i++) {
            var e = errors[i];
            if (e) {
                diagnostics.push({
                    severity: "error",
                    message: e.message(),
                    filePath: e.filePath() || null,
                    lineNumber: e.startingLineNumber() || null
                });
            }
        }
        var warnings = result.buildWarnings();
        for (var j = 0; j < warnings.length; j++) {
            var w = warnings[j];
            if (w) {
                diagnostics.push({
                    severity: "warning",
                    message: w.message(),
                    filePath: w.filePath() || null,
                    lineNumber: w.startingLineNumber() || null
                });
            }
        }
        JSON.stringify(diagnostics);
        """
    }

    /// Generates JXA script to clean the build folder.
    /// - Parameter scheme: The scheme to clean, or nil for the active scheme.
    static func jxaClean(scheme: String?) -> String {
        if let scheme = scheme {
            return """
            var xcode = Application("Xcode");
            var workspace = xcode.workspaceDocuments[0];
            var schemeToUse = "\(escapeJXAString(scheme))";
            xcode.clean(workspace, {scheme: schemeToUse});
            "clean triggered for scheme: " + schemeToUse;
            """
        } else {
            return """
            var xcode = Application("Xcode");
            var workspace = xcode.workspaceDocuments[0];
            xcode.clean(workspace);
            "clean triggered for active scheme";
            """
        }
    }

    /// Escapes a string for safe inclusion in a JXA script.
    /// Handles backslashes, quotes, and newlines.
    static func escapeJXAString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
