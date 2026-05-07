import Foundation

/// Executes system processes using Foundation's `Process` with async/await and timeout support.
struct ProcessExecutor: ProcessExecuting {

    func run(command: String, arguments: [String], timeout: Duration) async throws -> ProcessOutput {
        try await withThrowingTaskGroup(of: ProcessOutput?.self) { group in
            // Task 1: Execute the process
            group.addTask {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                try process.run()

                // Read output data before waiting, to avoid deadlocks with large output
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                process.waitUntilExit()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                let exitCode = process.terminationStatus

                return ProcessOutput(stdout: stdout, stderr: stderr, exitCode: exitCode)
            }

            // Task 2: Timeout
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil // nil signals timeout
            }

            // Race: take whichever finishes first
            guard let firstResult = try await group.next() else {
                throw XcodePowerError.xcodeUnresponsive(timeout: timeout)
            }

            // Cancel the remaining task
            group.cancelAll()

            guard let output = firstResult else {
                // nil means the timeout task won the race
                throw XcodePowerError.xcodeUnresponsive(timeout: timeout)
            }

            // Check for non-zero exit code
            if output.exitCode != 0 {
                throw XcodePowerError.jxaExecutionFailed(stderr: output.stderr, exitCode: output.exitCode)
            }

            return output
        }
    }
}
