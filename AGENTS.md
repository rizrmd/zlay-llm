# Zlay LLM Client - Agent Guide

This is a high-performance OpenAI-compatible LLM client written in Zig with full support for OpenAI Harmony encoding and streaming responses.

## Project Overview

- **Language**: Zig (no external dependencies beyond stdlib)
- **Purpose**: OpenAI-compatible LLM client with Harmony encoding support
- **Key Features**: Streaming responses, function calling, structured output, memory safety

## Build Commands

```bash
# Build executable (example program)
zig build

# Run the example program
zig build run

# Build library
zig build-lib src/main.zig

# Run all tests
zig test src/main.zig

# Run specific test files
zig test tests/client_tests.zig
zig test tests/function_calling_tests.zig

# Build executable manually
zig build-exe src/main.zig --name zlay-llm
```

## Environment Variables

- `OPENAI_API_KEY`: Required for API access (set in your environment or the client will prompt)
- `API_KEY`: Alternative API key (default: "93ac6b4e9c1c49b4b64fed617669e569.5nfnaoMbbNaKZ26I")
- `API_URL`: Alternative API URL (default: "https://api.z.ai/api/coding/paas/v4")
- `MODEL`: Alternative model name (default: "glm-4.5v")

## Project Structure

```
zlay-llm/
├── src/
│   ├── main.zig              # Main entry point, exports, and integration tests
│   ├── client.zig            # Core LLMClient interface
│   ├── models.zig            # OpenAI-compatible data structures
│   ├── harmony.zig           # Harmony encoding implementation
│   ├── harmony_parser.zig    # Streaming Harmony parser
│   └── http.zig              # HTTP client with streaming support
├── tests/
│   ├── client_tests.zig      # Core functionality tests
│   └── function_calling_tests.zig  # Function calling tests
├── build.zig                 # Zig build configuration
└── README.md
```

## Code Organization

### Core Components

- **LLMClient** (`src/client.zig`): Main client interface with OpenAI compatibility
- **Models** (`src/models.zig`): OpenAI-compatible request/response structures
- **Harmony** (`src/harmony.zig`): Special tokens and message formatting for gpt-oss models
- **HTTP** (`src/http.zig`): Streaming HTTP client with JSON parsing

### Key Patterns

1. **Memory Management**: All structs use explicit allocators and require `deinit()` calls
2. **Error Handling**: Comprehensive error unions with descriptive error types
3. **Streaming**: Native streaming support with Server-Sent Events (SSE)
4. **Harmony Format**: Special token-based encoding for gpt-oss models

## API Usage Patterns

### Client Initialization
```zig
var llm_client = client.LLMClient.init(allocator, api_key, "gpt-4", .{
    .use_harmony = false,  // Set to true for gpt-oss models
    .base_url = "https://api.openai.com/v1",
});
defer llm_client.deinit();
```

### Request Creation
```zig
const request = models.ChatCompletionRequest{
    .model = "gpt-4",
    .messages = &messages,
    .max_tokens = 100,
    .temperature = 0.7,
    .stream = false,
};
```

### Streaming Responses
```zig
var stream = try llm_client.streamChatCompletion(request);
defer stream.deinit();

while (try stream.next()) |chunk| {
    // Process chunk
}
```

## Harmony Encoding

Special tokens used for gpt-oss models:
- `start` (200006): `<|start|>`
- `end` (200007): `<|end|>`
- `message` (200008): `<|message|>`
- `channel` (200005): `<|channel|>`
- `constrain` (200003): `<|constrain|>`
- `return_token` (200002): `<|return|>`
- `call` (200012): `<|call|>`

### Message Structure
```
<|start|>role<|channel|>channel_name<|message|>content<|end|>
```

## Testing

### Test Categories
1. **Unit Tests**: Individual component functionality
2. **Integration Tests**: End-to-end API interactions
3. **Harmony Tests**: Special token handling and message formatting
4. **Function Calling**: Tool definitions and execution

### Running Tests
```bash
# All tests
zig test src/main.zig

# Specific test files
zig test tests/client_tests.zig
zig test tests/function_calling_tests.zig
```

## Memory Safety Rules

1. Always call `deinit()` on client instances
2. Use explicit allocators (typically `std.heap.page_allocator` for examples)
3. Free allocated strings and structures properly
4. Test with `zig test` to catch memory leaks

## Function Calling Support

Complete OpenAI function calling implementation:
- Tool definitions with JSON schema parameters
- Tool choice strategies (auto, none, required, specific)
- Streaming tool calls in real-time
- Response parsing and validation

## Important Gotchas

1. **Environment Variable**: Client expects `OPENAI_API_KEY` to be set
2. **Harmony vs Standard**: Use `use_harmony = true` only for gpt-oss models
3. **Memory Management**: Always pair `init()` with `deinit()`
4. **Streaming**: Call `deinit()` on stream objects when done
5. **JSON Parsing**: Large responses may need custom allocator strategies

## Development Guidelines

1. Follow Zig naming conventions (camelCase for functions, PascalCase for types)
2. Use comprehensive error types with descriptive messages
3. Include unit tests for all public APIs
4. Document Harmony token usage and special cases
5. Maintain OpenAI API compatibility in all interfaces