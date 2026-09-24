import Foundation
import XCTest
@testable import HudEXCore

final class RemindersFormatTests: XCTestCase {
    func testStandaloneSourceAcceptsMinimalReminderAndRoundTrips() throws {
        let source = """
        {"schemaVersion":3,"sourceID":"source-1","projects":[],"reminders":[
          {"id":"task-1","title":"Pay rent"}
        ]}
        """
        let document = try HudEXJSONCodec.decode(Data(source.utf8))
        XCTAssertTrue(document.projects.isEmpty)
        XCTAssertFalse(document.isEmpty)
        XCTAssertEqual(document.reminders.first?.title, "Pay rent")
        XCTAssertNil(document.reminders.first?.projectID)
        XCTAssertEqual(document.reminders.first?.priority, 0)
        XCTAssertFalse(document.reminders.first?.isCompleted ?? true)

        let encoded = try HudEXJSONCodec.encode(document)
        let decoded = try HudEXJSONCodec.decode(encoded)
        XCTAssertEqual(decoded.reminders.map(\.id), ["task-1"])
        XCTAssertEqual(decoded.sourceID, "source-1")
    }

    func testLegacyProjectReminderMovesToTopLevel() throws {
        let source = """
        {"schemaVersion":2,"sourceID":"old-source","projects":[
          {"id":"project-1","title":"Project","sections":[],"reminders":[
            {"id":"task-1","title":"Follow up","isCompleted":false,"priority":0,
             "reminderIdentifier":"native-1","syncFingerprint":"fingerprint"}
          ]}
        ]}
        """
        let migrated = try HudEXJSONCodec.decode(Data(source.utf8))
        XCTAssertEqual(migrated.reminders.first?.projectID, "project-1")
        XCTAssertEqual(migrated.reminders.first?.reminderIdentifier, "native-1")
        XCTAssertEqual(migrated.reminders.first?.syncFingerprint, "fingerprint")

        let encoded = try HudEXJSONCodec.encode(migrated)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 6)
        let projects = try XCTUnwrap(object["projects"] as? [[String: Any]])
        XCTAssertNil(projects.first?["reminders"])
        let reminders = try XCTUnwrap(object["reminders"] as? [[String: Any]])
        XCTAssertEqual(reminders.first?["projectID"] as? String, "project-1")
    }

    func testDuplicateIDsStopReconciliation() {
        let source = """
        {"schemaVersion":3,"projects":[],"reminders":[
          {"id":"same","title":"First"},{"id":"same","title":"Second"}
        ]}
        """
        XCTAssertThrowsError(try HudEXJSONCodec.decode(Data(source.utf8)))
    }

    func testOneFileContainsSeveralTasksForOneProject() throws {
        let source = """
        {"schemaVersion":4,"sourceID":"one-source","projects":[
          {"id":"p1","title":"Project","shortTitle":"P1","sections":[]}
        ],"reminders":[
          {"id":"r1","projectID":"p1","title":"First"},
          {"id":"r2","projectID":"p1","title":"Second","dueDate":"2026-10-01T09:00:00Z"}
        ]}
        """
        let document = try HudEXJSONCodec.decode(Data(source.utf8))
        XCTAssertEqual(document.projects.count, 1)
        XCTAssertEqual(document.reminders.filter { $0.projectID == "p1" }.count, 2)
        XCTAssertNotNil(document.reminders.last?.dueDate)
        XCTAssertEqual(try HudEXJSONCodec.decode(HudEXJSONCodec.encode(document)).reminders.count, 2)
        XCTAssertEqual(SourceLocator.defaultURL(homeDirectory: URL(fileURLWithPath: "/tmp/test-home")).lastPathComponent,
                       "HudEX.json")
        XCTAssertTrue(HudEXJSONCodec.defaultAIInstructions.contains(where: { $0.contains("actionable reminders") }))
    }

    func testExtendedReminderFieldsRoundTripAndOldFileDefaults() throws {
        let source = """
        {"schemaVersion":5,"projects":[],"reminders":[{
          "id":"task-1","title":"Visit office","dueDate":"2026-10-01T09:00:00Z",
          "startDate":"2026-10-01T08:00:00Z","location":"Campus office",
          "locationAlert":{"title":"Campus office","latitude":28.18,"longitude":112.94,
                           "radiusMeters":150,"trigger":"arrive"},
          "repeatRule":{"frequency":"weekly","interval":2},
          "earlyReminderMinutes":30,"priority":1,"isFlagged":true,"tags":["work"]
        }]}
        """
        let reminder = try XCTUnwrap(HudEXJSONCodec.decode(Data(source.utf8)).reminders.first)
        XCTAssertEqual(reminder.location, "Campus office")
        XCTAssertEqual(reminder.locationAlert?.trigger, .arrive)
        XCTAssertEqual(reminder.repeatRule?.interval, 2)
        XCTAssertEqual(reminder.earlyReminderMinutes, 30)
        XCTAssertEqual(reminder.priority, 1)
        XCTAssertTrue(reminder.isFlagged)
        XCTAssertEqual(reminder.tags, ["work"])
        let document = try HudEXJSONCodec.decode(Data(source.utf8))
        XCTAssertEqual(try HudEXJSONCodec.decode(HudEXJSONCodec.encode(document)).reminders.first, reminder)

        let legacy = try HudEXJSONCodec.decode(Data("""
        {"schemaVersion":4,"projects":[],"reminders":[{"id":"old","title":"Old"}]}
        """.utf8))
        XCTAssertNil(legacy.reminders.first?.locationAlert)
        XCTAssertNil(legacy.reminders.first?.repeatRule)
        XCTAssertEqual(legacy.reminders.first?.tags, [])
    }

    func testInvalidGeofenceIsRejected() {
        let source = """
        {"schemaVersion":5,"projects":[],"reminders":[{"id":"a","title":"Arrive",
        "locationAlert":{"title":"Place","latitude":120,"longitude":112,"radiusMeters":100,"trigger":"arrive"}}]}
        """
        XCTAssertThrowsError(try HudEXJSONCodec.decode(Data(source.utf8)))
    }
}
