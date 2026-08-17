# Contributing to WakeUpNeo

Thank you for your interest in contributing to **WakeUpNeo**! We are thrilled to welcome new contributors. Whether you are fixing a typo in documentation, reporting a bug, adding a new feature, or proposing an architectural enhancement, your help is deeply appreciated.

---

## 🌟 Getting Started

### Prerequisites

To build and run WakeUpNeo, you need:
- A Mac running **macOS 15 Sequoia** or later (Apple Silicon or Intel)
- **Xcode 16+** or Swift 6.0+ toolchain
- Git

### Local Setup

1. **Fork and Clone** the repository:
   ```bash
   git clone https://github.com/uysalserkan/WakeUpNeo.git
   cd WakeUpNeo
   ```

2. **Open in Xcode** or use the Swift Package Manager CLI:
   ```bash
   # Open directly in Xcode
   open Package.swift
   
   # Or build via command line
   swift build
   ```

3. **Run the Automated Test Suite**:
   ```bash
   swift test
   ```

4. **Install Locally**:
   ```bash
   make install
   ```

---

## 📐 Code Guidelines & Architecture

WakeUpNeo is designed to feel like a first-party Apple utility. When contributing code, please keep the following principles in mind:

### 1. Target Separation
- **`WakeUpNeoCore`**: All business logic, timers, power assertions, and file watchers belong here. **Never import `SwiftUI` into `WakeUpNeoCore`**.
- **`WakeUpNeo`**: The UI shell. SwiftUI views, menu bar extra scene, and settings tabs belong here.

### 2. Swift 6 Strict Concurrency
- The codebase builds with complete strict concurrency checking.
- Ensure all models and data structures passed across boundaries conform to `Sendable`.
- Use `@MainActor` for UI-bound coordinators (such as `SleepManager`).

### 3. Logging & Debugging
- **No `print()` statements in production code**. Use `AppLogger` (`OSLog` subsystem `com.wakeupneo.app`) instead:
  ```swift
  import OSLog
  private let logger = Logger(subsystem: "com.wakeupneo.app", category: "MyFeature")
  logger.info("[MyFeature] Starting task...")
  ```

### 4. Accessibility & Native Styling
- Use system semantic colors (`Color.primary`, `Color.secondary`, `Color.accentColor`) so the app looks fantastic in both Light and Dark mode.
- Use **SF Symbols** for all icons.
- Add `.accessibilityLabel` and `.accessibilityHint` to interactive elements.

---

## 🧪 Testing Your Changes

We take stability and battery-efficiency very seriously. Any new feature or bugfix should include corresponding unit or integration tests.

Before submitting a Pull Request, make sure all tests pass:

```bash
swift test
```

If you are adding new features, please add tests under `Tests/WakeUpNeoTests/` following our [4-Tier Test Architecture](TEST_INFRA.md).

---

## 🚀 Submitting a Pull Request

1. **Create a Feature Branch**:
   ```bash
   git checkout -b feature/my-amazing-feature
   ```
2. **Commit Your Changes**:
   ```bash
   git commit -m "feat(watchers): add support for custom download formats"
   ```
3. **Push to your Fork**:
   ```bash
   git push origin feature/my-amazing-feature
   ```
4. **Open a Pull Request** against the `main` branch. Provide a clear description of what changed and reference any relevant issues.

---

## 💬 Code of Conduct

We are committed to providing a friendly, safe, and welcoming environment for all contributors regardless of experience level. Please be respectful, constructive, and kind in all communications.

---

## 📄 License

By contributing to WakeUpNeo, you agree that your contributions will be licensed under the project's [MIT License](LICENSE).
