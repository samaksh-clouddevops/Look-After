# Task lifecycle simulation

Run the production task, recurrence, replanning and SQLite modules through 30 ordered days. Each open day reconstructs the store and view model from an isolated database under the temporary directory. Seven-day gaps, process reopening, duplicate rows, moves, completion/undo, urgent additions and project steps are covered.

```sh
swift test --package-path Tools/TaskSimulation --scratch-path /private/tmp/lookafter-task-simulation
TZ=America/Los_Angeles swift test --package-path Tools/TaskSimulation --scratch-path /private/tmp/lookafter-task-simulation --skip-build
```

Run from the repository root on macOS 26 with Xcode 26's Swift toolchain. Use the same package for both invocations; do not reuse a scratch directory from a different package.

The runner has 20 tests, including three complete month scenarios and parameterized late-night checks. It uses production recurrence sync, schedule persistence, AI response decoding, the preview Apply handler and on-disk SQLite. The calendar runs October 26–November 24, 2026; the Los Angeles run crosses the fall daylight-saving change. Each month records a daily diary as a Swift Testing attachment and prints its action count.

AI transport uses deterministic responses or an unavailable-service error. These tests exercise parsing, safe application, offline recovery and failure handling without external requests, credentials or token costs. They do not evaluate the quality of a live model's reasoning.

This separate runner lets the task lifecycle checks run even when unrelated legacy tests in the Features package do not compile. It does not replace the main package suites or device UI testing. All synthetic task data stays in temporary SQLite databases; no production task store is used.
