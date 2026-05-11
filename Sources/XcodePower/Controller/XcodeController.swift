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
    func build(scheme: String?, destination: String? = nil) async throws -> String {
        try await ensureXcodeReady(requireProject: true)
        let script = Self.jxaBuild(scheme: scheme, destination: destination)
        return try await executeJXA(script, timeout: Self.defaultTimeout)
    }

    /// Triggers test execution for the given scheme and optional test identifier.
    func test(scheme: String?, testIdentifier: String?, destination: String? = nil) async throws -> String {
        try await ensureXcodeReady(requireProject: true)
        let script = Self.jxaTest(scheme: scheme, testIdentifier: testIdentifier, destination: destination)
        return try await executeJXA(script, timeout: Self.defaultTimeout)
    }

    /// Triggers run action for the given scheme (nil = active scheme).
    func run(scheme: String?, destination: String? = nil) async throws -> String {
        try await ensureXcodeReady(requireProject: true)
        let script = Self.jxaRun(scheme: scheme, destination: destination)
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

    /// Lists all available run destinations in the active workspace.
    func listDestinations() async throws -> [DestinationInfo] {
        try await ensureXcodeReady(requireProject: false)
        let script = Self.jxaListDestinations()
        let output = try await executeJXA(script, timeout: Self.defaultTimeout)
        return parseDestinations(from: output)
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

    /// Parses destination info from JXA JSON output.
    private func parseDestinations(from output: String) -> [DestinationInfo] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[]" else { return [] }
        guard let data = trimmed.data(using: .utf8),
              let destinations = try? JSONDecoder().decode([DestinationInfo].self, from: data) else {
            return []
        }
        return destinations
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
    /// - Parameters:
    ///   - scheme: The scheme to build, or nil for the active scheme.
    ///   - destination: The run destination name, or nil for the active destination.
    static func jxaBuild(scheme: String?, destination: String? = nil) -> String {
        var script = """
        var xcode = Application("Xcode");
        var workspace = xcode.workspaceDocuments[0];

        """

        if let scheme = scheme {
            script += """
            var schemeToUse = "\(escapeJXAString(scheme))";
            workspace.activeScheme = workspace.schemes.whose({name: schemeToUse})[0];

            """
        }

        if let destination = destination {
            script += jxaSetDestination(destination) + "\n"
        }

        if scheme != nil {
            script += """
            var actionResult = xcode.build(workspace, {scheme: schemeToUse});
            """
        } else {
            script += """
            var actionResult = xcode.build(workspace);
            """
        }

        script += """

        var status = actionResult.status();
        while (status === "not yet started" || status === "running") {
            delay(2);
            status = actionResult.status();
        }
        status;
        """

        return script
    }

    /// Generates JXA script to trigger a test action.
    /// Like build, the test command is asynchronous. We poll actionResult.status()
    /// until it reaches a terminal state.
    /// - Parameters:
    ///   - scheme: The scheme to test, or nil for the active scheme.
    ///   - testIdentifier: Optional test class or method identifier.
    ///   - destination: The run destination name, or nil for the active destination.
    static func jxaTest(scheme: String?, testIdentifier: String?, destination: String? = nil) -> String {
        var script = """
        var xcode = Application("Xcode");
        var workspace = xcode.workspaceDocuments[0];

        """

        if let scheme = scheme {
            script += """
            var schemeToUse = "\(escapeJXAString(scheme))";
            workspace.activeScheme = workspace.schemes.whose({name: schemeToUse})[0];

            """
        }

        if let destination = destination {
            script += jxaSetDestination(destination) + "\n"
        }

        if let testIdentifier = testIdentifier {
            script += """
            var testId = "\(escapeJXAString(testIdentifier))";

            """
        }

        // Trigger the test and capture the action result
        if scheme != nil && testIdentifier != nil {
            script += """
            var actionResult = xcode.test(workspace, {scheme: schemeToUse, testIdentifier: testId});
            """
        } else if scheme != nil {
            script += """
            var actionResult = xcode.test(workspace, {scheme: schemeToUse});
            """
        } else if testIdentifier != nil {
            script += """
            var actionResult = xcode.test(workspace, {testIdentifier: testId});
            """
        } else {
            script += """
            var actionResult = xcode.test(workspace);
            """
        }

        // Poll until terminal status
        script += """

        var status = actionResult.status();
        while (status === "not yet started" || status === "running") {
            delay(2);
            status = actionResult.status();
        }
        status;
        """

        return script
    }

    /// Generates JXA script to trigger a run action.
    /// - Parameters:
    ///   - scheme: The scheme to run, or nil for the active scheme.
    ///   - destination: The run destination name, or nil for the active destination.
    static func jxaRun(scheme: String?, destination: String? = nil) -> String {
        var script = """
        var xcode = Application("Xcode");
        var workspace = xcode.workspaceDocuments[0];

        """

        if let scheme = scheme {
            script += """
            var schemeToUse = "\(escapeJXAString(scheme))";
            workspace.activeScheme = workspace.schemes.whose({name: schemeToUse})[0];

            """
        }

        if let destination = destination {
            script += jxaSetDestination(destination) + "\n"
        }

        if scheme != nil {
            script += """
            xcode.run(workspace, {scheme: schemeToUse});
            "run triggered for scheme: " + schemeToUse;
            """
        } else {
            script += """
            xcode.run(workspace);
            "run triggered for active scheme";
            """
        }

        return script
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

    /// Generates JXA script to list all available run destinations.
    static func jxaListDestinations() -> String {
        """
        var xcode = Application("Xcode");
        var workspace = xcode.workspaceDocuments[0];
        var destinations = workspace.runDestinations();
        var result = [];
        for (var i = 0; i < destinations.length; i++) {
            var d = destinations[i];
            result.push({
                name: d.name(),
                platform: d.platform() || null,
                architecture: d.architecture() || null
            });
        }
        JSON.stringify(result);
        """
    }

    /// Generates JXA snippet to set the active run destination by name.
    /// Returns the snippet to prepend to a build/test/run script.
    /// - Parameter destination: The destination name to select.
    static func jxaSetDestination(_ destination: String) -> String {
        """
        var destName = "\(escapeJXAString(destination))";
        var dests = workspace.runDestinations();
        for (var di = 0; di < dests.length; di++) {
            if (dests[di].name() === destName) {
                workspace.activeRunDestination = dests[di];
                break;
            }
        }
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
            workspace.activeScheme = workspace.schemes.whose({name: schemeToUse})[0];
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

    /// Generates JXA script to get the project file path from the frontmost workspace document.
    /// Returns the file path of the frontmost workspace document in Xcode.
    /// If multiple workspace documents are open, uses the frontmost one.
    static func jxaGetProjectPath() -> String {
        """
        var xcode = Application("Xcode");
        var docs = xcode.workspaceDocuments();
        if (docs.length === 0) {
            null;
        } else {
            var doc = docs[0];
            var filePath = doc.file().toString();
            filePath;
        }
        """
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
