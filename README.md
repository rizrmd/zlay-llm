# Zlay LLM Client

A high-performance, OpenAI-compatible LLM client written in Zig with full support for OpenAI Harmony encoding and streaming responses.

## Features

- **OpenAI Compatible**: Full compatibility with OpenAI API endpoints
- **Harmony Encoding Support**: Native support for OpenAI Harmony format used by gpt-oss models
- **Streaming Responses**: Real-time streaming with Server-Sent Events (SSE)
- **Function Calling**: Complete support for OpenAI function calling
- **Structured Output**: JSON schema-based structured output generation
- **Memory Safe**: Built with Zig's memory safety guarantees
- **Zero Dependencies**: No external dependencies beyond Zig's standard library

## Quick Start

```zig
const std = @import("std");
const client = @import("zlay-llm").client;
const models = @import("zlay-llm").models;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const api_key = std.posix.getenv("OPENAI_API_KEY") orelse return;
    
    // Initialize client
    var llm_client = client.LLMClient.init(allocator, api_key, "gpt-4", .{});
    defer llm_client.deinit();
    
    // Create messages
    const messages = [_]models.ChatMessage{
        .{ .role = "user", .content = "Hello, world!" },
    };
    
    // Create request
    const request = models.ChatCompletionRequest{
        .model = "gpt-4",
        .messages = &messages,
        .max_tokens = 100,
        .temperature = 0.7,
    };
    
    // Get response
    const response = try llm_client.createChatCompletion(request);
    std.debug.print("Response: {s}\n", .{response.choices[0].message.content.?});
}
```

## Harmony Format Support

For gpt-oss models that require Harmony encoding:

```zig
// Initialize with Harmony support
var harmony_client = client.LLMClient.init(allocator, api_key, "gpt-oss", .{
    .use_harmony = true,
});
defer harmony_client.deinit();

// Works with the same API!
const response = try harmony_client.createChatCompletion(request);
```

## Streaming

```zig
// Stream responses in real-time
var stream = try llm_client.streamChatCompletion(request);
defer stream.deinit();

while (try stream.next()) |chunk| {
    if (chunk.content.len > 0) {
        std.debug.print("{s}", .{chunk.content});
    }
    if (chunk.finish_reason) |reason| {
        std.debug.print("\nFinished: {s}\n", .{reason});
    }
}
```

## Function Calling

```zig
const tools = [_]models.ChatCompletionRequest.Tool{
    .{
        .function = .{
            .name = "get_weather",
            .description = "Get current weather",
            .parameters = std.json.Value{
                .object = std.json.ObjectMap.init(allocator),
            },
        },
    },
};

const request = models.ChatCompletionRequest{
    .model = "gpt-4",
    .messages = &messages,
    .tools = &tools,
    .tool_choice = .{ .auto = {} },
};

var stream = try llm_client.streamChatCompletion(request);
defer stream.deinit();

while (try stream.next()) |chunk| {
    if (chunk.tool_calls) |tool_calls| {
        for (tool_calls) |tool_call| {
            if (tool_call.function.name) |name| {
                std.debug.print("Tool call: {s}\n", .{name});
            }
        }
    }
}
```

## Harmony Format Details

The Harmony format uses special tokens to structure conversations:

- **Roles**: `system`, `developer`, `user`, `assistant`, `tool`
- **Channels**: `analysis`, `commentary`, `final`
- **Special Tokens**: `<|start|>`, `<|end|>`, `<|message|>`, `<|channel|>`, etc.

### Example Harmony Message

```
<|start|>assistant<|channel|>analysis<|message|>User asks: "What is 2 + 2?" Simple arithmetic.<|end|>
<|start|>assistant<|channel|>final<|message|>2 + 2 = 4.<|return|>
```

## Building

```bash
# Build the library
zig build-lib src/main.zig

# Build executable
zig build-exe src/main.zig --name zlay-llm

# Run tests
zig test src/main.zig
```

## Project Structure

```
zlay-llm/
├── src/
│   ├── main.zig          # Main entry point and exports
│   ├── client.zig        # Main LLM client interface
│   ├── models.zig        # OpenAI-compatible data structures
│   ├── harmony.zig       # Harmony encoding implementation
│   ├── harmony_parser.zig # Streaming Harmony parser
│   └── http.zig          # HTTP client with streaming support
├── examples/
│   └── basic_usage.zig   # Usage examples
├── tests/
│   └── client_tests.zig   # Comprehensive tests
└── README.md
```

## API Reference

### LLMClient

Main client interface for interacting with LLM APIs.

#### Methods

- `init(allocator, api_key, model, options)` - Initialize client
- `createChatCompletion(request)` - Non-streaming completion
- `streamChatCompletion(request)` - Streaming completion
- `deinit()` - Clean up resources

### Data Structures

- `ChatCompletionRequest` - Request parameters
- `ChatCompletionResponse` - Response data
- `ChatCompletionChunk` - Streaming chunk
- `StreamChunk` - Individual streaming chunk
- `Harmony.Message` - Harmony format message
- `Harmony.Role` - Message role (system, user, assistant, etc.)
- `Harmony.Channel` - Assistant channel (analysis, commentary, final)

## Testing

Run the comprehensive test suite:

```bash
zig test src/main.zig
```

## Examples

See `examples/basic_usage.zig` for complete usage examples including:

- Basic chat completions
- Streaming responses
- Function calling
- Harmony format usage
- Error handling

## License

This project is open source. See LICENSE file for details.

## Contributing

Contributions are welcome! Please ensure:

1. All tests pass
2. Code follows Zig style guidelines
3. Documentation is updated
4. Memory safety is maintained

## Performance

Built with Zig for maximum performance:

- Zero-copy operations where possible
- Minimal memory allocations
- Efficient string handling
- Native streaming support
- No runtime overhead from abstractions