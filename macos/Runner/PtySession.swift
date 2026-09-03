import Darwin
import Foundation

/// Runs an official CLI under a real pseudo-terminal and captures what it draws.
///
/// Some providers only show the authenticated user their quota inside an
/// interactive terminal panel. Those CLIs check `isatty` and refuse to render
/// when their output is a pipe, so a plain `Process` with pipes gets nothing
/// back. A PTY is the only way to run them the way a terminal would.
///
/// This is deliberately *not* a general-purpose command runner:
///
///  * only the executables in `allowedExecutables` can be launched,
///  * the process is always bounded by a timeout and always torn down,
///  * nothing is written to the child except the scripted keystrokes,
///  * the captured bytes are returned verbatim for Dart to interpret, so all
///    parsing — and all of the tests for it — live on one side.
///
/// It never reads the provider's credentials. The CLI authenticates itself, the
/// same as when the user runs it by hand.
enum PtySession {

    /// CLIs this app is allowed to drive.
    ///
    /// A whitelist rather than a free-form path: the Dart side is our own code,
    /// but a bug there should not be able to turn this into a way to run
    /// arbitrary programs.
    static let allowedExecutables: Set<String> = [
        "agy", "gemini", "claude", "codex",
    ]

    struct Step {
        /// Seconds after launch to send these bytes.
        let at: TimeInterval
        let keys: String
    }

    /// Finds an installed CLI, returning its absolute path.
    ///
    /// An app launched from Finder inherits a minimal `PATH` — typically just
    /// `/usr/bin:/bin:/usr/sbin:/sbin` — which contains none of the places these
    /// tools install to. Asking a login shell would work but means spawning one
    /// on every check, so the common locations are searched directly and the
    /// user's own `PATH` is honoured when the app happens to have one.
    static func locate(_ name: String) -> String? {
        guard allowedExecutables.contains(name) else { return nil }

        var candidates: [String] = []

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map(String.init))
        }

        let home = NSHomeDirectory()
        candidates.append(contentsOf: [
            "\(home)/.local/bin",       // agy, codex
            "/opt/homebrew/bin",        // Apple silicon Homebrew: gemini, claude
            "/usr/local/bin",           // Intel Homebrew
            "\(home)/.bun/bin",
            "\(home)/.deno/bin",
            "\(home)/.volta/bin",
            "\(home)/.nvm/versions/node",
            "\(home)/bin",
        ])

        let manager = FileManager.default
        var seen = Set<String>()
        for directory in candidates where seen.insert(directory).inserted {
            let candidate = (directory as NSString).appendingPathComponent(name)
            if manager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    struct Result {
        let output: String
        let exitCode: Int32?
        let timedOut: Bool
        let launched: Bool
        let failure: String?
    }

    /// Grace period between asking the child to stop and killing it.
    private static let terminationGrace: TimeInterval = 1.5

    static func run(
        executable: String,
        arguments: [String],
        steps: [Step],
        timeout: TimeInterval,
        columns: Int,
        rows: Int,
        workingDirectory: String?
    ) -> Result {
        let name = (executable as NSString).lastPathComponent
        guard allowedExecutables.contains(name) else {
            return Result(
                output: "",
                exitCode: nil,
                timedOut: false,
                launched: false,
                failure: "Executable not permitted: \(name)"
            )
        }

        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return Result(
                output: "",
                exitCode: nil,
                timedOut: false,
                launched: false,
                failure: "Not installed: \(executable)"
            )
        }

        var master: Int32 = 0
        var slave: Int32 = 0
        var size = winsize(
            ws_row: UInt16(rows),
            ws_col: UInt16(columns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        // `openpty` rather than `forkpty`: forking a process that already has a
        // Flutter engine, a window server connection, and several thread pools
        // in it is a good way to inherit a deadlock. `Process` does the fork
        // and exec for us, safely.
        guard openpty(&master, &slave, nil, nil, &size) == 0 else {
            return Result(
                output: "",
                exitCode: nil,
                timedOut: false,
                launched: false,
                failure: "Could not allocate a pseudo-terminal"
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        // A TUI lays itself out against these. Without them it either refuses
        // to draw or wraps its panel at 80 columns and splits the numbers we
        // came for across lines.
        environment["TERM"] = "xterm-256color"
        environment["COLUMNS"] = String(columns)
        environment["LINES"] = String(rows)
        process.environment = environment

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        do {
            try process.run()
        } catch {
            close(master)
            close(slave)
            return Result(
                output: "",
                exitCode: nil,
                timedOut: false,
                launched: false,
                failure: "Could not start \(name): \(error.localizedDescription)"
            )
        }

        // The parent has no further use for the slave end; leaving it open
        // means the read below never sees EOF when the child exits.
        close(slave)

        let captured = drive(
            master: master,
            steps: steps,
            timeout: timeout
        )

        terminate(process)
        close(master)

        return Result(
            output: String(decoding: captured.bytes, as: UTF8.self),
            exitCode: process.isRunning ? nil : process.terminationStatus,
            timedOut: captured.timedOut,
            launched: true,
            failure: nil
        )
    }

    // MARK: - Driving the session

    private static func drive(
        master: Int32,
        steps: [Step],
        timeout: TimeInterval
    ) -> (bytes: [UInt8], timedOut: Bool) {
        var bytes: [UInt8] = []
        var pending = steps.sorted { $0.at < $1.at }
        let start = Date()
        let deadline = start.addingTimeInterval(timeout)

        // How long to keep reading after the last keystroke, so the panel has
        // time to finish drawing before we tear the session down.
        let settleAfterLastStep: TimeInterval = 6
        var settleDeadline: Date?

        // Once the panel has drawn numbers and the CLI has gone quiet, there
        // is nothing left to wait for. Holding the session open for the full
        // settle regardless meant every refresh cost the same worst case even
        // when the answer had already arrived — which is most of what made
        // pressing Refresh feel like it had hung.
        let quietEnough: TimeInterval = 1.5
        var lastByteAt = Date()
        var sawFigures = false

        var buffer = [UInt8](repeating: 0, count: 65536)

        while Date() < deadline {
            var readSet = fd_set()
            fdZero(&readSet)
            fdSet(master, &readSet)

            var wait = timeval(tv_sec: 0, tv_usec: 200_000)
            let ready = select(master + 1, &readSet, nil, nil, &wait)

            if ready > 0 {
                let count = read(master, &buffer, buffer.count)
                if count > 0 {
                    bytes.append(contentsOf: buffer[0..<count])
                    lastByteAt = Date()
                    if !sawFigures {
                        sawFigures = Self.containsFigures(buffer[0..<count])
                    }
                } else {
                    // EOF: the child exited on its own.
                    break
                }
            } else if ready < 0 && errno != EINTR {
                break
            }

            let elapsed = Date().timeIntervalSince(start)
            while let next = pending.first, elapsed >= next.at {
                pending.removeFirst()
                _ = next.keys.withCString { pointer in
                    write(master, pointer, strlen(pointer))
                }
                if pending.isEmpty {
                    settleDeadline = Date().addingTimeInterval(settleAfterLastStep)
                }
            }

            if let settleDeadline, Date() > settleDeadline {
                return (bytes, false)
            }

            // Left early only with something to show for it. A quiet terminal
            // that never drew a figure is a CLI still starting up, or one
            // waiting on a prompt that was typed too soon — leaving then would
            // report "no panel" for a session that was about to produce one.
            if sawFigures,
               !pending.isEmpty,
               Date().timeIntervalSince(lastByteAt) > quietEnough {
                return (bytes, false)
            }
        }

        // Running out of the budget with steps still queued means the CLI never
        // got far enough to accept them — a stalled sign-in, most likely.
        return (bytes, !pending.isEmpty || Date() >= deadline)
    }

    /// Whether a chunk of terminal output contains a figure — a digit next to
    /// a percent sign.
    ///
    /// Deliberately crude. The native side does not parse these panels and
    /// must not start; this only answers "has the CLI printed a number yet",
    /// which is enough to tell a drawn panel from a banner.
    private static func containsFigures(_ chunk: ArraySlice<UInt8>) -> Bool {
        var sawDigit = false
        for byte in chunk {
            if byte >= 0x30 && byte <= 0x39 {
                sawDigit = true
            } else if byte == 0x25 {  // '%'
                if sawDigit { return true }
            } else if byte != 0x2E && byte != 0x20 {  // '.' and space
                sawDigit = false
            }
        }
        return false
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }

        process.interrupt()
        let giveUp = Date().addingTimeInterval(terminationGrace)
        while process.isRunning && Date() < giveUp {
            usleep(50_000)
        }

        if process.isRunning {
            process.terminate()
            let hardGiveUp = Date().addingTimeInterval(terminationGrace)
            while process.isRunning && Date() < hardGiveUp {
                usleep(50_000)
            }
        }

        // A TUI that ignored both signals would otherwise be left behind
        // holding the user's terminal session open.
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    // MARK: - fd_set helpers

    // `fd_set` is a fixed-size bitfield that Swift imports as a tuple, so the
    // usual FD_ZERO / FD_SET macros are not available.

    private static func fdZero(_ set: inout fd_set) {
        set.fds_bits = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private static func fdSet(_ fd: Int32, _ set: inout fd_set) {
        let index = Int(fd) / 32
        let bit = Int32(1 << (Int(fd) % 32))
        withUnsafeMutablePointer(to: &set.fds_bits) { pointer in
            pointer.withMemoryRebound(
                to: Int32.self,
                capacity: 32
            ) { bits in
                bits[index] |= bit
            }
        }
    }
}
