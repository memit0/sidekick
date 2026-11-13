import Foundation

enum Shell {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private final class Box: @unchecked Sendable { var data = Data() }

    /// Runs a process, optionally feeding stdin. Terminates it on task cancellation or timeout.
    @discardableResult
    static func run(
        _ path: String,
        _ args: [String],
        env: [String: String]? = nil,
        cwd: URL? = nil,
        stdin: Data? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if let env { process.environment = env }
        if let cwd { process.currentDirectoryURL = cwd }

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let inPipe: Pipe? = stdin == nil ? nil : Pipe()
        process.standardInput = inPipe ?? FileHandle.nullDevice

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }

                    if let timeout {
                        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                            if process.isRunning { process.terminate() }
                        }
                    }
                    if let stdin, let inPipe {
                        DispatchQueue.global().async {
                            inPipe.fileHandleForWriting.write(stdin)
                            try? inPipe.fileHandleForWriting.close()
                        }
                    }

                    // Drain both pipes concurrently so a chatty process can't block on a full buffer.
                    let out = Box(), err = Box()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global().async {
                        out.data = outPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.enter()
                    DispatchQueue.global().async {
                        err.data = errPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    process.waitUntilExit()
                    group.wait()

                    continuation.resume(returning: Result(
                        status: process.terminationStatus,
                        stdout: String(decoding: out.data, as: UTF8.self),
                        stderr: String(decoding: err.data, as: UTF8.self)
                    ))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
