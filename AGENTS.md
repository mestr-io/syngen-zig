# AGENTS.md - syngen-zig

## Project Overview
`syngen-zig` is a high-performance synthetic Slack export generator written in Zig 0.15. It is designed to generate large, realistic Slack-compliant export archives (JSON files in a specific directory structure) for testing eDiscovery tools, legal AI, and data processing pipelines.

This project is a modern successor to the original `syngen` project implemented in C99 (https://github.com/mestr-io/syngen).

## Findings and Schemas
The design of `syngen-zig` leverages proven components and algorithms from the original C99 implementation, now verified and expanded by analyzing real Slack exports (documented in `MODELS.md`):

### 1. Verified Data Models
- **User**: Identified in `users.json`. Includes detailed `profile` objects, timezone info, and boolean permission flags.
- **Channel**: Identified in `channels.json`. Includes `id`, `name`, `members`, `topic`, and `purpose`.
- **Message**: Identified in `<channel>/YYYY-MM-DD.json`. Supports `blocks` (Rich Text), `client_msg_id`, `user_profile` subsets, and complex threading metadata.
- **Reactions & Files**: Real exports include a `reactions` array and `files` array for attachments.

### 2. Core Algorithms
- **Activity Distribution**: Use of the **Box-Muller transform** to generate a Gaussian distribution for channel and user activity. This ensures some channels and users are "louder" than others, mimicking real-world behavior.
- **Message Generation**:
  - Messages are generated across a time window and then **sorted by timestamp** before being processed for threading.
  - **Threading Logic**: A two-pass approach where messages have a 20% chance to start a thread and a configurable `thread_prob` to become a reply to an active thread within a 3-day window.
- **Export Mapping**: Grouping messages by channel name and date (`YYYY-MM-DD.json`) using a sorted reference index to minimize file handle overhead.

### 3. Slack Compatibility
- Adheres to the Slack Export structure:
  - `users.json` at root.
  - `channels.json` at root.
  - `<channel_name>/<date>.json` for message logs.

## Development Standards (Zig 0.15)
`syngen-zig` must follow modern Zig idiomatic patterns to ensure safety and performance:

### 1. Memory Management
- **Explicit Allocation**: No hidden allocations. Functions should accept an `Allocator`.
- **Strategy**: Use `std.heap.GeneralPurposeAllocator` for long-lived state and `std.heap.ArenaAllocator` for batch generation tasks (e.g., generating 100k messages) to ensure fast cleanup.

### 2. Error Handling
- Use Zig's error union types (`!T`) and the `try` keyword.
- Ensure all I/O and allocation failures are handled gracefully.

### 3. JSON Serialization
- Leverage `std.json` for all serialization.
- Use struct-to-JSON mapping where possible for type safety.

### 4. Testing Mandate
- **All functions must be tested.**
- Every logic-heavy component (faker, generator, date calculator) must have associated unit tests in its respective file or a dedicated `tests/` directory.
- Use `std.testing` for assertions and `zig build test` for verification.

## Architecture
- `src/models.zig`: Struct definitions for Slack entities.
- `src/faker.zig`: Synthetic data generation (names, IDs, lorem ipsum).
- `src/generator.zig`: High-level generation logic and algorithms (Gaussian picking, threading).
- `src/exporter.zig`: File system operations and JSON writing.
- `src/main.zig`: CLI entry point.

## Verification
- Run `zig build` to ensure compilation.
- Run `zig build test` to verify all components.
