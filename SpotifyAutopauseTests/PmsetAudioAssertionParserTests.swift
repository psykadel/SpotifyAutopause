import XCTest
@testable import SpotifyAutopause

final class PmsetAudioAssertionParserTests: XCTestCase {
    private let parser = PmsetAudioAssertionParser()

    func testReturnsEmptyArrayWhenNoAudioOutputAssertionsExist() {
        XCTAssertEqual(parser.extractAudioOutputPIDs(from: noAudioOutputSample), [])
    }

    func testExtractsMultipleAudioOutputPIDsAndRemovesDuplicates() {
        XCTAssertEqual(parser.extractAudioOutputPIDs(from: multipleAudioOutputSample), [123, 456])
    }

    func testIgnoresMalformedEntriesWithoutCreatedForPIDLine() {
        XCTAssertEqual(parser.extractAudioOutputPIDs(from: malformedAudioOutputSample), [])
    }

    func testExtractsOwningPIDFromDirectAudioPlayingAssertions() {
        XCTAssertEqual(parser.extractAudioOutputPIDs(from: directAudioPlayingSample), [1182])
    }
}

private let noAudioOutputSample = """
2026-03-23 15:42:58 -0500
Assertion status system-wide:
   PreventUserIdleSystemSleep    0
   PreventUserIdleDisplaySleep   0
Listed by owning process:
  pid 111(loginwindow): [0x000000000001] 00:00:03 NoIdleSleepAssertion named: "background"
     Details: Resources: cpu
"""

private let multipleAudioOutputSample = """
2026-03-23 15:42:58 -0500
Assertion status system-wide:
Listed by owning process:
  pid 123(Safari): [0x000000000111] 00:00:10 PreventUserIdleDisplaySleep named: "Created for PID: 123"
     Details: Resources: audio-out
  pid 456(Shortcuts Events): [0x000000000222] 00:00:08 PreventUserIdleDisplaySleep named: "Created for PID: 456"
     Details: Resources: audio-out
  pid 123(Safari): [0x000000000333] 00:00:04 PreventUserIdleDisplaySleep named: "Created for PID: 123"
     Details: Resources: audio-out
"""

private let malformedAudioOutputSample = """
2026-03-23 15:42:58 -0500
Assertion status system-wide:
Listed by owning process:
  pid 999(helper): [0x000000000444] 00:00:04 PreventUserIdleDisplaySleep named: "audio helper"
     Details: Resources: audio-out
"""

private let directAudioPlayingSample = """
2026-03-23 15:42:58 -0500
Assertion status system-wide:
Listed by owning process:
   pid 1182(firefox): [0x0000164500019a64] 00:00:20 NoIdleSleepAssertion named: "audio-playing"
   pid 1182(firefox): [0x0000164500059a65] 00:00:20 NoDisplaySleepAssertion named: "video-playing"
"""
