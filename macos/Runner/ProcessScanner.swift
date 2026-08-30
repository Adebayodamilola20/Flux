import Darwin
import Foundation

/// Finds running processes by executable name, and identifies the application
/// hosting each one.
///
/// Uses `libproc`, which reads only what `ps` would show: pid, executable path,
/// parent pid, and start time. It never reads another process's memory,
/// arguments, or environment, and it requires no additional entitlement or
/// user permission.
enum ProcessScanner {

    struct Match {
        let pid: pid_t
        let name: String
        /// Owning application resolved by walking the parent chain, e.g.
        /// "Terminal", "iTerm2", "Visual Studio Code".
        let host: String?
        /// Unix epoch seconds.
        let startedAt: Double?
    }

    /// `PROC_PIDTBSDINFO` from `<libproc.h>`. The header's constants are C
    /// macros, so they are not imported into Swift and are restated here.
    private static let bsdInfoFlavor: Int32 = 3

    /// `PROC_PIDPATHINFO_MAXSIZE` (`4 * MAXPATHLEN`).
    private static let pathBufferSize = 4 * Int(MAXPATHLEN)

    /// How far up the parent chain to look for an owning `.app` bundle. Deep
    /// enough for `claude → zsh → login → Terminal`, shallow enough to stay
    /// cheap.
    private static let maxAncestorDepth = 6

    /// Returns every running process whose executable base name is in [names].
    static func find(names: [String]) -> [Match] {
        guard !names.isEmpty else { return [] }
        let wanted = Set(names.map { $0.lowercased() })

        let pids = allPids()
        guard !pids.isEmpty else { return [] }

        var matches: [Match] = []
        for pid in pids where pid > 0 {
            guard let path = executablePath(of: pid) else { continue }
            let base = (path as NSString).lastPathComponent
            guard wanted.contains(base.lowercased()) else { continue }

            matches.append(
                Match(
                    pid: pid,
                    name: base,
                    host: resolveHost(startingFrom: pid),
                    startedAt: startTime(of: pid)
                )
            )
        }

        // Most recently started first, so the caller's "first" match is the
        // session the user most likely just started.
        return matches.sorted { ($0.startedAt ?? 0) > ($1.startedAt ?? 0) }
    }

    // MARK: - libproc access

    private static func allPids() -> [pid_t] {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else { return [] }

        let capacity = Int(byteCount) / MemoryLayout<pid_t>.stride
        var buffer = [pid_t](repeating: 0, count: capacity)

        let written = buffer.withUnsafeMutableBufferPointer { pointer -> Int32 in
            proc_listpids(
                UInt32(PROC_ALL_PIDS),
                0,
                pointer.baseAddress,
                Int32(pointer.count * MemoryLayout<pid_t>.stride)
            )
        }
        guard written > 0 else { return [] }

        let count = Int(written) / MemoryLayout<pid_t>.stride
        return Array(buffer.prefix(count))
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: pathBufferSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func bsdInfo(of pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let read = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, bsdInfoFlavor, 0, pointer, size)
        }
        return read == size ? info : nil
    }

    private static func parentPid(of pid: pid_t) -> pid_t? {
        guard let info = bsdInfo(of: pid) else { return nil }
        let parent = pid_t(info.pbi_ppid)
        return parent > 0 ? parent : nil
    }

    private static func startTime(of pid: pid_t) -> Double? {
        guard let info = bsdInfo(of: pid) else { return nil }
        return Double(info.pbi_start_tvsec)
    }

    // MARK: - Host resolution

    /// Walks up the parent chain looking for the first process that lives
    /// inside an application bundle, and returns that bundle's display name.
    private static func resolveHost(startingFrom pid: pid_t) -> String? {
        var current = pid
        for _ in 0..<maxAncestorDepth {
            guard let parent = parentPid(of: current), parent > 1 else {
                return nil
            }
            if let path = executablePath(of: parent),
               let name = appName(fromExecutablePath: path) {
                return name
            }
            current = parent
        }
        return nil
    }

    /// Extracts "Terminal" from
    /// "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal".
    private static func appName(fromExecutablePath path: String) -> String? {
        guard let range = path.range(of: ".app/Contents/MacOS/") else {
            return nil
        }
        let bundlePath = String(path[path.startIndex..<range.lowerBound]) + ".app"
        let bundleName = (bundlePath as NSString).lastPathComponent

        // Prefer the localized display name so, for example, the bundle
        // "iTerm.app" reports as "iTerm2".
        if let bundle = Bundle(path: bundlePath),
           let display = (bundle.localizedInfoDictionary?["CFBundleDisplayName"]
                            ?? bundle.infoDictionary?["CFBundleDisplayName"]
                            ?? bundle.infoDictionary?["CFBundleName"]) as? String,
           !display.isEmpty {
            return display
        }

        return (bundleName as NSString).deletingPathExtension
    }
}
