# Simplified API Design Proposal

## 🎯 Current Issue:
We have 4 separate methods for tools:
- `chat()` / `chatWithTools()`
- `stream()` / `streamWithTools()`

## 💡 Better Solution:
Tools should be **optional parameters** on core methods:

```zig
// Core method with optional tools
pub fn chat(
    self: *LLMClient, 
    request: models.ChatCompletionRequest,
    tool_executor: ?*const fn (tool_name: []const u8, arguments: []const u8, allocator: std.mem.Allocator) []const u8 = null,
    max_iterations: ?u32 = null,
) !models.ChatCompletionResponse

// Core streaming with optional tool callbacks
pub fn stream(
    self: *LLMClient,
    request: models.ChatCompletionRequest,
    tool_callback: ?*const fn (tool_calls: []const models.ChatCompletionChunk.StreamToolCall) void = null,
    content_callback: ?*const fn (content: []const u8) void = null,
) !ChatCompletionStream
```

## 🔄 Usage Examples:

### Simple Chat (No Tools)
```zig
const response = try client.chat(request);
```

### Chat with Tools
```zig
const response = try client.chat(
    request, 
    executeTool,           // Optional tool executor
    max_iterations: 5      // Optional iteration limit
);
```

### Simple Stream (No Tools)
```zig
var stream = try client.stream(request);
defer stream.deinit();

while (try stream.next()) |chunk| {
    if (chunk.content) |content| {
        std.debug.print("{s}", .{content});
    }
}
```

### Stream with Tool Callbacks
```zig
var stream = try client.stream(
    request,
    handleToolCalls,        // Optional tool callback
    handleContent           // Optional content callback
);
defer stream.deinit();

while (try stream.next()) |chunk| {
    // Callbacks handle tools automatically
}
```

## ✅ Benefits:

### 🎯 Simpler API:
- **2 core methods** instead of 4
- **Optional parameters** for tools
- **Unified interface** for all use cases
- **No method proliferation**

### 📚 Better Documentation:
- One set of examples covers all cases
- Clear parameter descriptions
- Progressive complexity in examples

### 🏗️ Cleaner Design:
- **Tools as features**, not separate methods
- **Optional pattern** instead of multiple methods
- **Single responsibility** per method
- **Modern API design**

## 🚀 Migration:

### Old API:
```zig
// Simple
const response = try client.chat(request);

// Tools
const response = try client.chatWithTools(request, 5, execute);

// Stream  
var stream = try client.stream(request);

// Stream with tools
var stream = try client.streamWithTools(request, handleTools, handleContent);
```

### New API:
```zig
// Simple (unchanged)
const response = try client.chat(request);

// Tools (simpler)
const response = try client.chat(request, executeTool, 5);

// Stream (unchanged)
var stream = try client.stream(request);

// Stream with tools (simpler)
var stream = try client.stream(request, handleTools, handleContent);
```

**Result: Same functionality with half the methods!**