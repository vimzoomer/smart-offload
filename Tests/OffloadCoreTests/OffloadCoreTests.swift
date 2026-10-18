import Testing
@testable import OffloadCore

@Test func versionIsSet() {
    #expect(!OffloadCore.version.isEmpty)
}
