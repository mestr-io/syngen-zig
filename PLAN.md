# Implementation Plan: syngen-zig

Synthetic Slack Export Generator in Zig 0.15.

## 1. Project Vision
`syngen-zig` is a modern, high-performance CLI tool to generate realistic Slack-compliant export archives. It succeeds the original C99 implementation by providing better memory safety, native JSON handling, and a more robust testing suite.

## 2. Technical Requirements
- **Language**: Zig 0.15.0
- **Build System**: Zig Build (`build.zig`)
- **JSON**: Native `std.json` for serialization.
- **I/O**: Native `std.fs` for directory and file management.
- **Compression**: System `zip` for archive creation.

## 3. CLI Specification
```bash
syngen-zig [options] <output_filename.zip>
```
**Options:**
- `-u, --users <count>`: Number of users (default: 10)
- `-c, --channels <count>`: Number of channels (default: 5)
- `-m, --messages <count>`: Total messages (default: 1000)
- `-t, --threads <prob>`: Threading probability 0.0-1.0 (default: 0.1)
- `-d, --days <count>`: Time window in days (default: 30)

## 4. Implementation Phases

### Phase 1: Core Foundation & Models - **Completed**
- [x] Define `User`, `Channel`, and `Message` structs in `src/models.zig`.
- [x] Implement `User` and `Channel` serialization according to `MODELS.md`.
- [x] Implement `Message` serialization including `blocks` (Rich Text) and `thread_ts`.
- [x] Setup `build.zig` with proper optimization levels and test targets.

### Phase 2: Synthetic Data (Faker) - **Completed**
- [x] Expand `src/faker.zig` with real-world name datasets (extracted from C99 project).
- [x] Implement Lorem Ipsum generator for `text` and `blocks`.
- [x] Implement Random ID generator (`U...`, `C...`, `T...`).
- [x] Implement `avatar_hash` (32-char hex) and Gravatar URL generation.
- [x] **Test**: Unit tests for all faker functions.

### Phase 3: Generation Logic - **Completed**
- [x] Implement `Gaussian` distribution utility for realistic activity spread.
- [x] Implement `Generator` struct to orchestrate:
    - User creation with unique IDs and profiles.
    - Channel creation with membership assignment.
    - Message generation with timestamp distribution.
- [x] Implement Two-Pass Threading Logic:
    - Pass 1: Generate sorted messages.
    - Pass 2: Assign threads and replies based on probability.
- [x] **Test**: Verify message distribution and threading integrity.

### Phase 4: Exporter & File System - **Completed**
- [x] Implement `Exporter` module:
    - Create directory structure: `users.json`, `channels.json`, `<channel>/YYYY-MM-DD.json`.
    - Handle date rounding and message grouping.
    - Efficient file writing using buffered I/O.
- [x] Implement Zip Archiving:
    - Use system `zip` to create the final Slack-compatible archive.
- [x] **Test**: Verify output archive structure against real Slack exports.

### Phase 5: CLI & Integration - **Completed**
- [x] Implement CLI argument parsing in `src/main.zig`.
- [x] Implement progress reporting (e.g., "Generating users...", "Writing messages...").
- [x] End-to-end integration tests: Generate an export and verify it with `slack-export-viewer` or similar tools.

## 5. Rules & Guidelines
- **No Global State**: All components must accept an `Allocator`.
- **Memory Safety**: Use `ArenaAllocator` for generation cycles to ensure zero leaks.
- **Testing**: Every function MUST have a corresponding `test` block.
- **Performance**: Aim for < 1s generation time for 100k messages.
- **Formatting**: Strictly follow `zig fmt`.

## 6. Bug Fixes
- **Large Export File Size**: Fixed issue where `zip` appended data to existing archives across multiple runs. Added explicit deletion of target zip file before creation.
- **JSON Compatibility**: Fixed `users.json` schema to match real Slack exports (specifically `status_emoji_display_info` and `fields`).
