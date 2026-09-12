import Darwin
import Foundation

/// Reads HudEX's own resource usage with public libproc APIs.
///
/// Used by the Advanced settings pane, and — when `HUDEX_PERF_LOG` points at a
/// file — by the performance verification run, which appends one line every
/// 30 seconds so idle cost can be measured over minutes instead of guessed.
struct PerformanceSnapshot: Equatable {
    var residentBytes: UInt64
    var cpuTimeSeconds: Double
    var threadCount: Int
    var wakeups: UInt64
    var uptimeSeconds: Double

    /// Average CPU since launch. For a utility that should idle near 0 %, this
    /// is the number that matters.
    var averageCPUPercent: Double {
        guard uptimeSeconds > 0 else { return 0 }
        return cpuTimeSeconds / uptimeSeconds * 100
    }

    var residentMegabytes: Double { Double(residentBytes) / 1_048_576 }
}

enum PerformanceMonitor {
    static func sample() -> PerformanceSnapshot {
        var info = rusage_info_v4()
        var resident: UInt64 = 0
        var cpuSeconds: Double = 0
        var wakeups: UInt64 = 0

        let result = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, rebound)
            }
        }
        if result == 0 {
            resident = info.ri_phys_footprint
            cpuSeconds = Double(info.ri_user_time + info.ri_system_time) / 1_000_000_000
            wakeups = info.ri_interrupt_wkups &+ info.ri_pkg_idle_wkups
        }

        return PerformanceSnapshot(
            residentBytes: resident,
            cpuTimeSeconds: cpuSeconds,
            threadCount: ProcessInfo.processInfo.activeProcessorCount > 0
                ? threadCount(of: getpid())
                : 0,
            wakeups: wakeups,
            uptimeSeconds: ProcessInfo.processInfo.systemUptime
        )
    }

    private static func threadCount(of pid: pid_t) -> Int {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threadList else {
            return 0
        }
        // The array is allocated by the kernel and must be given back.
        let size = vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)), size)
        return Int(threadCount)
    }

    /// Starts the optional 30 s performance log (`HUDEX_PERF_LOG=<path>`).
    static func startLoggingIfRequested() -> Timer? {
        guard let path = ProcessInfo.processInfo.environment["HUDEX_PERF_LOG"] else { return nil }
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data().write(to: url)
        }
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            let snapshot = sample()
            let line = String(
                format: "%.3f rss=%.1fMB cpu_total=%.3fs avg_cpu=%.3f%% threads=%d wakeups=%llu\n",
                Date().timeIntervalSince1970,
                snapshot.residentMegabytes,
                snapshot.cpuTimeSeconds,
                snapshot.averageCPUPercent,
                snapshot.threadCount,
                snapshot.wakeups
            )
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            }
        }
        timer.tolerance = 5
        return timer
    }
}
