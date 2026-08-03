import XCTest
@testable import LookAfterAI
import LookAfterCore

final class GLMKeyManagerTests: XCTestCase {
    private var secretStore: InMemorySecretStore!
    private var manager: GLMKeyManager!

    override func setUp() {
        super.setUp()
        secretStore = InMemorySecretStore()
        manager = GLMKeyManager(secretStore: secretStore, metadataKey: "glmKeyRecords.tests")
        manager.clearAllForTesting()
    }

    override func tearDown() {
        manager.clearAllForTesting()
        secretStore.removeAll()
        super.tearDown()
    }

    func testAddKeyStoresMetadataAndSecret() throws {
        let record = try manager.addKey(name: "Personal", secret: "glm-test-key-1234567890", isDefault: true)

        XCTAssertEqual(manager.allRecords().count, 1)
        XCTAssertEqual(record.name, "Personal")
        XCTAssertEqual(record.maskedSuffix, "7890")
        XCTAssertEqual(manager.secret(for: record.id), "glm-test-key-1234567890")
    }

    func testEligibleKeysSkipDisabledAndExhausted() throws {
        let first = try manager.addKey(name: "Primary", secret: "glm-primary-key-1234567890", isDefault: true)
        _ = try manager.addKey(name: "Backup", secret: "glm-backup-key-1234567890")

        try manager.updateKey(id: first.id, isEnabled: false)
        manager.markExhausted(keyId: manager.allRecords().last!.id)

        XCTAssertTrue(manager.eligibleKeys().isEmpty)
    }

    func testReorderUpdatesPriority() throws {
        let first = try manager.addKey(name: "A", secret: "glm-a-key-1234567890")
        let second = try manager.addKey(name: "B", secret: "glm-b-key-1234567890")

        manager.reorderKeys(ids: [second.id, first.id])

        XCTAssertEqual(manager.allRecords().first?.name, "B")
    }

    func testDeleteRemovesKeychainSecret() throws {
        let record = try manager.addKey(name: "Temp", secret: "glm-temp-key-1234567890")
        try manager.deleteKey(id: record.id)

        XCTAssertTrue(manager.allRecords().isEmpty)
        XCTAssertNil(manager.secret(for: record.id))
    }
}

final class GLMQuotaDetectionTests: XCTestCase {
    func testDetectsQuotaExceededError() {
        XCTAssertTrue(GLMService.isQuotaOrRateLimitError(GLMServiceError.quotaExceeded))
    }

    func testDetectsQuotaMessageInGenericError() {
        let error = GLMServiceError.networkError("HTTP 429: quota exceeded for metric")
        XCTAssertTrue(GLMService.isQuotaOrRateLimitError(error))
    }

    func testDoesNotTreatInvalidKeyAsQuotaError() {
        XCTAssertFalse(GLMService.isQuotaOrRateLimitError(GLMServiceError.invalidAPIKey))
    }
}

final class GLMKeyRecordTests: XCTestCase {
    func testMaskedDisplayNeverShowsFullKey() {
        let record = GLMKeyRecord(name: "Work", maskedSuffix: "AB12")
        XCTAssertEqual(record.maskedDisplay, "************AB12")
    }

    func testDisabledKeyStatus() {
        var record = GLMKeyRecord(name: "Old", isEnabled: false)
        XCTAssertEqual(record.status, .disabled)
    }
}
