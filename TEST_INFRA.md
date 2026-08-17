# WakeUpNeo: Test Infrastructure & Contributor QA Guide

This document outlines the testing philosophy, architectural design, test harnesses, and patterns used to ensure the reliability and concurrency safety of **WakeUpNeo**.

---

## 1. Testing Philosophy

WakeUpNeo employs an opaque-box, requirement-driven, multi-tiered testing strategy designed to prevent regressions, memory leaks, concurrency races, and power assertion dangling:

1. **Deterministic Concurrency**: All tests adhere to Swift 6 strict concurrency rules. Shared mutable state is strictly prohibited in tests.
2. **Hermetic File Isolation**: Every file system test operates in an isolated temporary directory created on demand and recursively cleaned up upon deinitialization (RAII).
3. **No Dangling OS Assertions**: Mock services are used for power assertion unit testing to prevent tests from modifying the host machine's power state during test runs.
4. **Adversarial & Stress Testing**: Rigorous evaluation of edge cases including NaN durations, burst file churn, rapid start/stop toggles, and malformed unicode paths.

---

## 2. Test Suite Architecture

```
Tests/WakeUpNeoTests/
├── Fixtures/
│   └── TestTempDirectory.swift         # RAII isolated temporary directory harness
│
├── Mocks/
│   ├── MockSleepService.swift          # Test double for IOKit / ProcessInfo assertions
│   └── MockFileWatchingService.swift   # Test double for event-driven file monitoring
│
├── Tier 1: Unit & Domain Tests
│   ├── DownloadPatternMatcherTests.swift
│   ├── FileStabilityCheckerTests.swift
│   ├── FileWatcherTests.swift
│   ├── SettingsTests.swift
│   ├── SleepManagerTests.swift
│   └── TimerTests.swift
│
├── Tier 2: Boundary & Adversarial Tests
│   ├── AdversarialFileStabilizationTests.swift
│   ├── AdversarialM1ChallengeTests.swift
│   └── AdversarialM3SettingsChallengeTests.swift
│
├── Tier 3: Lifecycle & UI Integration Tests
│   ├── SleepManagerFileWatcherTests.swift
│   ├── AdversarialM2ChallengeTests.swift
│   ├── AdversarialM2TransitionsAndNotificationsTests.swift
│   ├── AdversarialM3ChallengeTests.swift
│   └── UIIntegrationTests.swift
│
└── Tier 4: Real-World Scenarios
    └── Tier4RealWorldScenariosTests.swift
```

---

## 3. Test Harnesses & Utilities

### `TestTempDirectory` (Hermetic File Isolation)
Located in `Tests/WakeUpNeoTests/Fixtures/TestTempDirectory.swift`:

```swift
let tempDir = try TestTempDirectory()
let fileURL = try tempDir.createFile(named: "download.crdownload", contents: "payload")
// Automatically deleted when tempDir falls out of scope
```

- Generates unique temporary directories under `/tmp/WakeUpNeoTests-*`.
- Provides convenience helpers for writing chunks, appending data, creating nested directory bundles (Safari `.download`), and atomic renames.
- Cleans up all files recursively on `deinit`.

### `MockSleepService` (Power Assertion Double)
Located in `Tests/WakeUpNeoTests/Mocks/MockSleepService.swift`:

- Conforms to `SleepPreventionService`.
- Tracks `startCallCount`, `stopCallCount`, and `isRunning` state in a thread-safe manner.
- Supports `shouldThrowOnStart` to simulate OS-level IOKit permission rejections.

### `MockFileWatchingService` (Watcher Double)
Located in `Tests/WakeUpNeoTests/Mocks/MockFileWatchingService.swift`:

- Conforms to `FileWatchingService`.
- Simulates download state changes, target file stabilization events, and error propagation without requiring actual disk I/O when testing higher-level coordinators like `SleepManager`.

---

## 4. How to Write New Tests

### Writing a Unit Test (Tier 1)
When adding new pure domain logic or utility functions:
```swift
import XCTest
@testable import WakeUpNeoCore

final class MyFeatureTests: XCTestCase {
    func testMyFeatureBehavior() throws {
        // Arrange
        let matcher = DownloadPatternMatcher()
        // Act
        let result = matcher.isTemporaryDownload("file.part")
        // Assert
        XCTAssertTrue(result)
    }
}
```

### Writing a File Watcher Test (Tier 2/3)
When testing file system interactions:
```swift
func testFileStabilization() async throws {
    let tempDir = try TestTempDirectory()
    let fileURL = try tempDir.createFile(named: "export.mp4", contents: "initial")
    
    let checker = FileStabilityChecker(settleDuration: 0.2)
    XCTAssertFalse(checker.isStable(url: fileURL))
    
    try await Task.sleep(nanoseconds: 250_000_000)
    XCTAssertTrue(checker.isStable(url: fileURL))
}
```

---

## 5. Running Tests Locally

Run the entire test suite via the command line:

```bash
swift test
```

To run a specific test suite or individual test:

```bash
swift test --filter SleepManagerTests
swift test --filter Tier4RealWorldScenariosTests/testScenario1ChromeLargeFileDownloadSimulation
```
