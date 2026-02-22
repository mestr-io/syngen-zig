# syngen-zig

A modern, high-performance synthetic Slack export generator written in Zig 0.15.

## Overview
`syngen-zig` generates realistic, Slack-compliant export archives (ZIP containing JSON) for testing eDiscovery tools, legal AI, and data processing pipelines. It mimics real-world activity using Gaussian distributions for user/channel engagement and simulates complex conversation threads.

## Requirements
- **Zig 0.15.0** or higher.
- **zip** utility (system command) for finalizing archives.

## Getting Started

### Build
To compile the project in safe release mode:
```bash
make build
```
The executable will be located at `zig-out/bin/syngen_zig`.

### Run
To generate a synthetic export:
```bash
make run ARGS="-u 20 -c 10 -m 5000 my_export.zip"
```

**CLI Options:**
- `-u, --users <count>`: Number of users to generate (default: 10)
- `-c, --channels <count>`: Number of channels to generate (default: 5)
- `-m, --messages <count>`: Total number of messages (default: 1000)
- `-t, --threads <prob>`: Probability of a message starting/joining a thread (0.0-1.0, default: 0.1)
- `-d, --days <count>`: Time window in days for message timestamps (default: 30)

### Test
To run the comprehensive test suite (unit tests + memory leak checks):
```bash
make test
```

### Lint
To check if the source code follows the Zig formatting standard:
```bash
make lint
```

## Logging
Execution details and performance metrics are written to `syngen_log.log` in the current working directory. Each entry includes a Unix timestamp and the module scope (e.g., generator, exporter).

## Performance Optimizations
`syngen-zig` is optimized for high-volume generation:
- **Multi-threading**: Utilizes all available CPU cores via `std.Thread.Pool`.
- **Lock-Free Memory**: Each worker thread uses its own `ArenaAllocator` to eliminate global allocator locks.
- **Parallel I/O**: Message logs are written to disk in parallel across channels.
- **Streaming JSON**: Serializes data directly to disk buffers to minimize memory footprint.

## Documentation
- **[MODELS.md](MODELS.md)**: Detailed JSON schemas for Slack compatibility.
- **[ARCHITECTURE.md](ARCHITECTURE.md)**: Data flow, multi-pass algorithms, and threading strategy.
- **[PLAN.md](PLAN.md)**: Project implementation history and roadmap.

## Architecture
- `src/models.zig`: Slack entity definitions and JSON schemas.
- `src/faker.zig`: Synthetic data generation (names, lorem ipsum, IDs).
- `src/generator.zig`: Core logic for activity distribution and threading.
- `src/exporter.zig`: Slack directory structure management and archive finalization.

## Project History
`syngen-zig` is the successor to the original [syngen](https://github.com/mestr-io/syngen) project written in C99. It adopts modern safety standards while expanding support for Rich Text (`blocks`) and complex metadata found in modern Slack exports.
