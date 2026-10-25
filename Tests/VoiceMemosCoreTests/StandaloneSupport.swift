#if CORE_STANDALONE_TESTS
import Foundation

// The standalone runner executes the exact XCTest test bodies on CLT-only Macs.
// In an Xcode toolchain this file is empty and XCTest supplies these assertions.
class XCTestCase {
    private var teardown: [() throws -> Void] = []
    func addTeardownBlock(_ body: @escaping () throws -> Void) { teardown.append(body) }
    func cleanUp() throws {
        defer { teardown = [] }
        for body in teardown.reversed() { try body() }
    }
}
private struct UnwrapFailure: Error {}
func XCTUnwrap<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) throws -> T {
    guard let value else { throw UnwrapFailure() }
    return value
}
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    precondition(lhs == rhs, "\(lhs) != \(rhs)", file: file, line: line)
}
func XCTAssertEqual(_ lhs: Double, _ rhs: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) {
    precondition(abs(lhs - rhs) <= accuracy, "\(lhs) != \(rhs) ± \(accuracy)", file: file, line: line)
}
func XCTAssertNotEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    precondition(lhs != rhs, "\(lhs) == \(rhs)", file: file, line: line)
}
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(value, "Expected true", file: file, line: line)
}
func XCTAssertFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(!value, "Expected false", file: file, line: line)
}
func XCTAssertNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    precondition(value == nil, "Expected nil", file: file, line: line)
}
func XCTAssertNotNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    precondition(value != nil, "Expected non-nil", file: file, line: line)
}
func XCTAssertLessThan<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    precondition(lhs < rhs, "\(lhs) is not less than \(rhs)", file: file, line: line)
}
func XCTAssertGreaterThan<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    precondition(lhs > rhs, "\(lhs) is not greater than \(rhs)", file: file, line: line)
}
func XCTFail(_ message: String, file: StaticString = #file, line: UInt = #line) {
    preconditionFailure(message, file: file, line: line)
}

@main
enum StandaloneCoreTests {
    @MainActor
    static func main() async throws {
        let tests = VoiceMemosCoreTests()
        let checks: [(String, () async throws -> Void)] = [
            ("analysis and silence detection", { try tests.testAnalysisIdentifiesSilenceAndProducesBoundedWaveform() }),
            ("persistence, folders, search, favorites and recovery", { try await tests.testLibraryPersistsFoldersSearchFavoritesAndRecovery() }),
            ("duplicate ownership and guarded permanent deletion", { try await tests.testDuplicateOwnsItsAudioAndPermanentDeleteRequiresTrash() }),
            ("failed-write rollback", { try tests.testFailedMetadataWriteLeavesInMemoryStateUnchanged() }),
            ("corrupt library preservation", { try tests.testCorruptLibraryCannotBeOverwritten() }),
            ("trash retention boundaries", { try await tests.testTrashRetentionKeepsActiveAndUnexpiredAudio() }),
            ("path traversal rejection", { try await tests.testLibraryRejectsPathTraversalMetadata() }),
            ("trim and exact original restoration", { try await tests.testTrimRetainsOriginalAndRestoreRecoversExactAudio() }),
            ("delete and replace interval audio content", { try await tests.testDeleteAndReplaceAudioIntervals() }),
            ("real speech enhancement", { try tests.testSpeechEnhancementCreatesSeparateProcessedAudio() }),
            ("real playback transport and prepare cancellation", { try await tests.testPlaybackTransportAndCancelledPreparation() })
        ]
        for (name, check) in checks {
            try await check()
            try tests.cleanUp()
            print("PASS: \(name)")
        }
        print("\(checks.count) core checks passed.")
    }
}
#endif
