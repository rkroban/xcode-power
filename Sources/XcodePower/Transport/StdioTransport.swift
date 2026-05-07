import Foundation

/// Handles low-level reading from stdin and writing to stdout for JSON-RPC communication.
///
/// Supports two framing modes:
/// - Newline-delimited JSON (primary): messages separated by newline characters
/// - Content-Length header framing (compatibility): HTTP-style headers followed by content
///
/// Note: This is intentionally NOT an actor. Stdin reading is done on a dedicated thread
/// to avoid blocking the cooperative thread pool, and stdout writing is synchronous and
/// protected by a lock.
final class StdioTransport: @unchecked Sendable {
    private let inputHandle: FileHandle
    private let outputHandle: FileHandle
    private let writeLock = NSLock()

    /// Header prefix used in Content-Length framing mode.
    private static let contentLengthHeader = "Content-Length: "

    init(
        inputHandle: FileHandle = .standardInput,
        outputHandle: FileHandle = .standardOutput
    ) {
        self.inputHandle = inputHandle
        self.outputHandle = outputHandle
    }

    /// Writes a JSON-RPC response message to stdout using Content-Length framing.
    ///
    /// - Parameter data: The JSON data to write
    func writeMessage(_ data: Data) {
        writeLock.lock()
        defer { writeLock.unlock() }

        // Use Content-Length framing for output (standard MCP framing)
        let header = "Content-Length: \(data.count)\r\n\r\n"
        if let headerData = header.data(using: .utf8) {
            outputHandle.write(headerData)
        }
        outputHandle.write(data)
    }

    /// Starts the read loop on a dedicated thread, yielding messages as an AsyncStream.
    ///
    /// The stream terminates when stdin is closed (EOF).
    ///
    /// - Returns: An AsyncStream that yields each incoming message as Data
    func messages() -> AsyncStream<Data> {
        let inputHandle = self.inputHandle
        return AsyncStream { continuation in
            // Use a dedicated thread for blocking stdin reads so we don't
            // block the Swift concurrency cooperative thread pool.
            let thread = Thread {
                while !Thread.current.isCancelled {
                    do {
                        let message = try Self.readNextMessage(from: inputHandle)
                        continuation.yield(message)
                    } catch {
                        // EOF or read error — finish the stream
                        continuation.finish()
                        return
                    }
                }
                continuation.finish()
            }
            thread.name = "XcodePower.StdioTransport.Reader"
            thread.qualityOfService = .userInitiated
            thread.start()

            continuation.onTermination = { _ in
                thread.cancel()
            }
        }
    }

    // MARK: - Private Static Helpers (no actor isolation, run on dedicated thread)

    /// Reads the next complete JSON-RPC message from the given file handle.
    ///
    /// Detects framing mode automatically:
    /// - If the input starts with "Content-Length:", reads using header framing
    /// - Otherwise, reads a single newline-delimited line as a message
    private static func readNextMessage(from handle: FileHandle) throws -> Data {
        guard let line = readLine(from: handle) else {
            throw StdioTransportError.inputClosed
        }

        if line.hasPrefix(contentLengthHeader) {
            return try readContentLengthFramedMessage(from: handle, headerLine: line)
        } else {
            guard let data = line.data(using: .utf8), !data.isEmpty else {
                throw StdioTransportError.invalidEncoding
            }
            return data
        }
    }

    /// Reads a Content-Length framed message after the header line has been read.
    private static func readContentLengthFramedMessage(from handle: FileHandle, headerLine: String) throws -> Data {
        // Parse the content length value
        let lengthString = String(headerLine.dropFirst(contentLengthHeader.count))
        guard let contentLength = Int(lengthString.trimmingCharacters(in: .whitespaces)), contentLength > 0 else {
            throw StdioTransportError.invalidContentLength(headerLine)
        }

        // Read and discard any additional headers until we hit an empty line
        while let nextLine = readLine(from: handle) {
            if nextLine.isEmpty || nextLine == "\r" {
                break
            }
        }

        // Read exactly contentLength bytes
        let data = handle.readData(ofLength: contentLength)
        guard data.count == contentLength else {
            throw StdioTransportError.unexpectedEndOfInput(
                expected: contentLength,
                received: data.count
            )
        }

        return data
    }

    /// Reads a single line from the given file handle, stripping the trailing newline.
    /// Returns nil on EOF.
    private static func readLine(from handle: FileHandle) -> String? {
        var lineData = Data()

        while true {
            let byte = handle.readData(ofLength: 1)
            if byte.isEmpty {
                // EOF
                if lineData.isEmpty {
                    return nil
                }
                break
            }

            let char = byte[byte.startIndex]
            if char == UInt8(ascii: "\n") {
                break
            }
            // Strip \r for \r\n line endings
            if char == UInt8(ascii: "\r") {
                continue
            }
            lineData.append(byte)
        }

        return String(data: lineData, encoding: .utf8)
    }
}

// MARK: - Errors

/// Errors specific to the stdio transport layer.
enum StdioTransportError: Error, Sendable {
    /// stdin was closed (EOF reached).
    case inputClosed

    /// Data could not be decoded as UTF-8.
    case invalidEncoding

    /// The Content-Length header value could not be parsed.
    case invalidContentLength(String)

    /// Fewer bytes were available than the Content-Length header specified.
    case unexpectedEndOfInput(expected: Int, received: Int)
}
