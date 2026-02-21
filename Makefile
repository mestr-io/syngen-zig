.PHONY: build run test lint clean

# Default target
build:
	zig build -Doptimize=ReleaseSafe

# Run the application
# Usage: make run ARGS="-u 10 -c 5 -m 1000 export.zip"
run:
	zig build run -- $(ARGS)

# Run all tests
test:
	zig build test --summary all

# Check formatting
lint:
	zig fmt --check src/*.zig

# Clean build artifacts
clean:
	rm -rf zig-out .zig-cache
