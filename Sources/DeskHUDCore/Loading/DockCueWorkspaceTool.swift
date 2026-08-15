import Foundation

public enum DockCueCheckStatus: String, Codable, Equatable, Sendable {
    case ok
    case warn
    case fail
}

public struct DockCueCheck: Codable, Equatable, Sendable {
    public var label: String
    public var status: DockCueCheckStatus
    public var message: String

    public init(label: String, status: DockCueCheckStatus, message: String) {
        self.label = label
        self.status = status
        self.message = message
    }
}

public struct DockCueDoctorReport: Codable, Equatable, Sendable {
    public var directory: String
    public var checks: [DockCueCheck]

    public var failures: Int { checks.filter { $0.status == .fail }.count }
    public var warnings: Int { checks.filter { $0.status == .warn }.count }
    public var isOK: Bool { failures == 0 }

    public init(directory: String, checks: [DockCueCheck]) {
        self.directory = directory
        self.checks = checks
    }
}

public enum DockCueWorkspaceError: Error, CustomStringConvertible, Equatable, Sendable {
    case fileExists(String)
    case writeFailed(String)

    public var description: String {
        switch self {
        case .fileExists(let path): return "File already exists: \(path)"
        case .writeFailed(let message): return "Write failed: \(message)"
        }
    }
}

public struct DockCueContext: Codable, Equatable, Sendable {
    public var maxCharsLeft: Int?
    public var maxCharsRight: Int?
    public var maxCharsPerLine: Int?
    public var leftWidth: Int?
    public var rightWidth: Int?
    public var updatedAt: String?
}

public struct DockCueWorkspaceTool: Sendable {
    private let loader: HUDFileLoader

    public init(loader: HUDFileLoader = HUDFileLoader()) {
        self.loader = loader
    }

    public func doctor(directory: URL) -> DockCueDoctorReport {
        report(directory: directory, configRequired: false, includeContext: true)
    }

    public func validateAll(directory: URL) -> DockCueDoctorReport {
        report(directory: directory, configRequired: true, includeContext: false)
    }

    public func loadContext(directory: URL) -> Result<DockCueContext, HUDFileLoaderError> {
        loader.decode(DockCueContext.self, from: directory.appendingPathComponent("hud_context.json"))
    }

    public func initialize(directory: URL, overwrite: Bool = false) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files: [(String, String)] = [
            ("config.json", Self.defaultConfig),
            ("hud_leftDock.json", Self.defaultLeftSlot),
            ("hud_rightDock.json", Self.defaultRightSlot)
        ]

        var written: [URL] = []
        for (name, content) in files {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path), !overwrite {
                throw DockCueWorkspaceError.fileExists(url.path)
            }
            do {
                try Data(content.utf8).write(to: url, options: .atomic)
                written.append(url)
            } catch {
                throw DockCueWorkspaceError.writeFailed(error.localizedDescription)
            }
        }
        return written
    }

    private func report(directory: URL, configRequired: Bool, includeContext: Bool) -> DockCueDoctorReport {
        var checks: [DockCueCheck] = []
        checks.append(checkConfig(directory.appendingPathComponent("config.json"), required: configRequired))
        checks.append(checkSlot(directory.appendingPathComponent("hud_leftDock.json"), label: "left slot", required: true))
        checks.append(checkSlot(directory.appendingPathComponent("hud_rightDock.json"), label: "right slot", required: true))
        if includeContext {
            checks.append(checkContext(directory.appendingPathComponent("hud_context.json")))
        }
        return DockCueDoctorReport(directory: directory.path, checks: checks)
    }

    private func checkConfig(_ url: URL, required: Bool) -> DockCueCheck {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return DockCueCheck(label: "config", status: required ? .fail : .warn, message: "missing config.json")
        }
        switch loader.loadConfig(from: url) {
        case .success:
            return DockCueCheck(label: "config", status: .ok, message: "config.json")
        case .failure(let error):
            return DockCueCheck(label: "config", status: .fail, message: error.description)
        }
    }

    private func checkSlot(_ url: URL, label: String, required: Bool) -> DockCueCheck {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return DockCueCheck(label: label, status: required ? .fail : .warn, message: "missing \(url.lastPathComponent)")
        }
        switch loader.loadSlotContent(from: url) {
        case .success:
            return DockCueCheck(label: label, status: .ok, message: url.lastPathComponent)
        case .failure(let error):
            return DockCueCheck(label: label, status: .fail, message: error.description)
        }
    }

    private func checkContext(_ url: URL) -> DockCueCheck {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return DockCueCheck(label: "context", status: .warn, message: "hud_context.json missing; launch DockCue once to generate width hints")
        }
        switch loader.decode(DockCueContext.self, from: url) {
        case .success(let context):
            let left = context.maxCharsLeft.map(String.init) ?? "?"
            let right = context.maxCharsRight.map(String.init) ?? "?"
            return DockCueCheck(label: "context", status: .ok, message: "maxCharsLeft=\(left), maxCharsRight=\(right)")
        case .failure(let error):
            return DockCueCheck(label: "context", status: .fail, message: error.description)
        }
    }

    public static let defaultConfig = """
    {
      "version": 1,
      "effectProfile": "low",
      "fullscreenMode": "overlay",
      "displays": "primary",
      "fixedDisplayID": null,
      "backgroundStyle": "clear",
      "calendarEvents": false,
      "launchAtLogin": false,
      "hideMenuBar": false,
      "watchDirectory": null,
      "debugLogging": false,
      "window": {
        "width": 0,
        "height": 82,
        "margin": 18,
        "cornerRadius": 14,
        "opacity": 0.84,
        "maxLines": 2,
        "contentDensity": "comfortable",
        "fontSize": 13,
        "textOpacity": 0.85,
        "scrollIntervalSeconds": 4,
        "leftPresentation": "pagerRail",
        "rightPresentation": "stack"
      }
    }
    """

    public static let defaultLeftSlot = """
    {
      "sections": [
        {
          "id": "now",
          "title": "Now",
          "items": [
            { "id": "focus", "type": "text", "kind": "today", "title": "Focus", "subtitle": "Write useful state here" }
          ]
        }
      ],
      "items": []
    }
    """

    public static let defaultRightSlot = """
    {
      "sections": [
        {
          "id": "context",
          "title": null,
          "items": [
            { "id": "context", "type": "text", "kind": "focus", "title": "DockCue", "subtitle": "Quiet Dock-side cues from local files" }
          ]
        }
      ],
      "items": []
    }
    """
}
