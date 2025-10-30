# Zlay LLM Client - API Methods Review

## 🎯 Public API Methods Overview

### 1. LLMClient Core Methods

#### `init(allocator, api_key, model, options) -> LLMClient`
**Purpose**: Initialize the LLM client
```zig
var client = LLMClient.init(allocator, api_key, model, .{
    .base_url = "https://api.z.ai/api/coding/paas/v4",
    .use_harmony = false,
});
```

#### `deinit() -> void`
**Purpose**: Clean up client resources
```zig
defer client.deinit();
```

#### `createChatCompletion(request) -> ChatCompletionResponse`
**Purpose**: Get a non-streaming chat completion
```zig
const response = try client.createChatCompletion(request);
```

#### `streamChatCompletion(request) -> ChatCompletionStream`
**Purpose**: Start streaming chat completion
```zig
var stream = try client.streamChatCompletion(request);
defer stream.deinit();
while (try stream.next()) |chunk| {
    // Handle streaming chunks
}
```

#### `createChatCompletionWithToolLoop(request, max_iterations, tool_executor) -> ChatCompletionResponse`
**Purpose**: Automatic tool use loop handling
```zig
const response = try client.createChatCompletionWithToolLoop(
    request,
    5, // max iterations
    executeTool,
);
```

#### `streamChatCompletionWithToolCallback(request, tool_callback, content_callback) -> ChatCompletionStream`
**Purpose**: Streaming with real-time tool call detection
```zig
var stream = try client.streamChatCompletionWithToolCallback(
    request,
    handleToolCalls,  // Called when tools detected
    handleContent,   // Called for content chunks
);
```

### 2. ChatCompletionStream Methods

#### `next() -> ?StreamChunk`
**Purpose**: Get next streaming chunk
```zig
while (try stream.next()) |chunk| {
    if (chunk.content) |content| {
        std.debug.print("Content: {s}\n", .{content});
    }
    if (chunk.tool_calls) |tools| {
        // Handle tool calls
    }
}
```

#### `deinit() -> void`
**Purpose**: Clean up stream resources
```zig
defer stream.deinit();
```

### 3. Data Structures

#### `ChatCompletionRequest`
```zig
const request = ChatCompletionRequest{
    .model = "glm-4.5v",
    .messages = &messages,
    .max_tokens = 100,
    .temperature = 0.7,
    .tools = &tools,
    .tool_choice = .{ .auto = {} },
};
```

#### `StreamChunk`
```zig
pub const StreamChunk = struct {
    content: ?[]const u8,
    role: ?[]const u8,
    finish_reason: ?[]const u8,
    tool_calls: ?[]const StreamToolCall,
};
```

## 🔄 Interaction Patterns

### Pattern 1: Simple Chat (Non-Streaming)
```zig
const response = try client.createChatCompletion(request);
const content = response.choices[0].message.content.?;
```

### Pattern 2: Streaming Chat
```zig
var stream = try client.streamChatCompletion(request);
defer stream.deinit();

while (try stream.next()) |chunk| {
    if (chunk.content) |content| {
        std.debug.print("{s}", .{content});
    }
}
```

### Pattern 3: Tool Use Loop (Automatic)
```zig
const response = try client.createChatCompletionWithToolLoop(
    request,
    max_iterations: 5,
    tool_executor: myToolExecutor,
);
```

### Pattern 4: Tool Use with Streaming (Real-time)
```zig
var stream = try client.streamChatCompletionWithToolCallback(
    request,
    handleToolCalls,  // Intercept tool calls immediately
    handleContent,   // Stream content as it arrives
);
```

## 🎛️ Tool Choice Options

```zig
// Let model decide when to use tools
.tool_choice = .{ .auto = {} }

// Never use tools
.tool_choice = .{ .none = {} }

// Must use at least one tool
.tool_choice = .{ .required = {} }

// Use specific tool
.tool_choice = .{ .function = .{ .name = "get_weather" } }
```

## 📊 Response Handling

### Non-Streaming Response
```zig
if (response.choices.len > 0) {
    const choice = response.choices[0];
    const content = choice.message.content orelse "";
    const tool_calls = choice.message.tool_calls;
    
    std.debug.print("Response: {s}\n", .{content});
    
    if (tool_calls) |calls| {
        for (calls) |call| {
            std.debug.print("Tool: {s}\n", .{call.function.name.?});
        }
    }
}
```

### Streaming Response
```zig
while (try stream.next()) |chunk| {
    if (chunk.content) |content| {
        // Handle content incrementally
    }
    
    if (chunk.tool_calls) |tools| {
        for (tools) |tool_call| {
            // Execute tool immediately if needed
        }
    }
    
    if (chunk.finish_reason) |reason| {
        std.debug.print("Stream finished: {s}\n", .{reason});
    }
}
```

## 🚀 Advanced Usage

### Conversation State Management
```zig
var messages = std.ArrayList(models.ChatMessage).init(allocator);
defer messages.deinit();

try messages.append(.{ .role = "user", .content = "Hello" });

// Add responses and continue conversation
try messages.append(.{ .role = "assistant", .content = response });

const next_request = ChatCompletionRequest{
    .model = model,
    .messages = messages.items,
    // ...
};
```

### Error Handling
```zig
const response = client.createChatCompletion(request) catch |err| switch (err) {
    error.NetworkError => return error.RetryNeeded,
    error.RateLimitError => {
        std.time.sleep(5 * std.time.ns_per_s);
        return try client.createChatCompletion(request);
    },
    else => return err,
};
```

## 📈 Performance Considerations

### Memory Management
```zig
// Always clean up properly
defer client.deinit();
defer stream.deinit();

// Use proper string handling
const content = response.choices[0].message.content orelse "";
allocator.free(content); // If you own it
```

### Reuse Connections
```zig
// Initialize once, reuse many times
var client = LLMClient.init(allocator, api_key, model, options);
defer client.deinit();

for (requests) |request| {
    const response = try client.createChatCompletion(request);
    // Process response...
}
```

## 🎯 Method Selection Guide

| Use Case | Recommended Method | Why |
|-----------|-------------------|------|
| Simple Q&A | `createChatCompletion()` | Fast, simple, non-streaming |
| Real-time UI | `streamChatCompletion()` | Immediate content display |
| Tool Automation | `createChatCompletionWithToolLoop()` | Automatic tool handling |
| Interactive Tools | `streamChatCompletionWithToolCallback()` | Real-time tool detection |
| Harmony Format | `options.use_harmony = true` | gpt-oss model support |

## 🔧 Configuration Options

```zig
const ClientOptions = struct {
    base_url: ?[]const u8 = null,
    use_harmony: bool = false,
    timeout_seconds: u32 = 60,
};
```

## ✅ Best Practices

1. **Always use `defer`** for cleanup
2. **Check response.choices.len** before accessing
3. **Handle null content** with orelse
4. **Use streaming** for real-time applications
5. **Implement proper error handling**
6. **Reuse client instances** for multiple requests
7. **Manage conversation state** with ArrayList
8. **Use tool loops** for complex workflows