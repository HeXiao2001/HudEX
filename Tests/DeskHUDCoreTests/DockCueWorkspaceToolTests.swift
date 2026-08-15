import XCTest
@testable import DeskHUDCore

final class DockCueWorkspaceToolTests: XCTestCase {
    func testDoctorReportsValidWorkspaceWithMissingContextAsWarning() throws {
        let dir = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeValidWorkspaceFiles(to: dir)

        let report = DockCueWorkspaceTool().doctor(directory: dir)

        XCTAssertTrue(report.isOK)
        XCTAssertEqual(report.failures, 0)
        XCTAssertEqual(report.warnings, 1)
        XCTAssertEqual(report.checks.first(where: { $0.label == "context" })?.status, .warn)
    }

    func testValidateAllFailsWhenRequiredSlotIsMissing() throws {
        let dir = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("{}", to: dir.appendingPathComponent("config.json"))
        try write(#"{"items":[]}"#, to: dir.appendingPathComponent("hud_leftDock.json"))

        let report = DockCueWorkspaceTool().validateAll(directory: dir)

        XCTAssertFalse(report.isOK)
        XCTAssertEqual(report.failures, 1)
        XCTAssertEqual(report.checks.first(where: { $0.label == "right slot" })?.status, .fail)
    }

    func testInitializeCreatesWorkspaceFilesAndRefusesOverwriteByDefault() throws {
        let dir = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tool = DockCueWorkspaceTool()

        let created = try tool.initialize(directory: dir)
        XCTAssertEqual(Set(created.map(\.lastPathComponent)), ["config.json", "hud_leftDock.json", "hud_rightDock.json"])
        XCTAssertThrowsError(try tool.initialize(directory: dir))

        let report = tool.validateAll(directory: dir)
        XCTAssertTrue(report.isOK)
    }

    private func makeWorkspace() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockCueWorkspaceToolTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeValidWorkspaceFiles(to dir: URL) throws {
        try write("{}", to: dir.appendingPathComponent("config.json"))
        try write(#"{"items":[]}"#, to: dir.appendingPathComponent("hud_leftDock.json"))
        try write(#"{"items":[]}"#, to: dir.appendingPathComponent("hud_rightDock.json"))
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }
}
