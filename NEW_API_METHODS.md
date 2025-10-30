# Zlay LLM Client - API Methods Review (Updated Names)

## 🎯 Public API Methods Overview (NEW NAMES IMPLEMENTED)

### 1. LLMClient Core Methods (Renamed)

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

#### `chat(request) -> ChatCompletionResponse` (NEW NAME!)
**Purpose**: Get a non-streaming chat completion
```zig
const response = try client.chat(request);
```

#### `stream(request) -> ChatCompletionStream` (NEW NAME!)
**Purpose**: Start streaming chat completion
```zig
var stream = try client.stream(request);
defer stream.deinit();
while (try stream.next()) |chunk| {
    // Handle streaming chunks
}
```

#### `chatWithTools(request, max_iterations, tool_executor) -> ChatCompletionResponse` (NEW NAME!)
**Purpose**: Automatic tool use loop handling
```zig
const response = try client.chatWithTools(request, 5, executeTool);
```

#### `streamWithTools(request, tool_callback, content_callback) -> ChatCompletionStream` (NEW NAME!)
**Purpose**: Streaming with real-time tool call detection
```zig
var stream = try client.streamWithTools(request, handleToolCalls, handleContent);
```

### 2. Deprecated Methods (Still Available with Warnings)

#### `createChatCompletion(request)` → `chat(request)`
#### `streamChatCompletion(request)` → `stream(request)`
#### `createChatCompletionWithToolLoop()` → `chatWithTools()`
#### `streamChatCompletionWithToolCallback()` → `streamWithTools()`

### 3. ChatCompletionStream Methods

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

## 🔄 Interaction Patterns (Updated)

### Pattern 1: Simple Chat (NEW METHOD)
```zig
const response = try client.chat(request);
const content = response.choices[0].message.content.?;
```

### Pattern 2: Streaming Chat (NEW METHOD)
```zig
var stream = try client.stream(request);
defer stream.deinit();

while (try stream.next()) |chunk| {
    if (chunk.content) |content| {
        std.debug.print("{s}", .{content});
    }
}
```

### Pattern 3: Tool Use Loop (NEW METHOD)
```zig
const response = try client.chatWithTools(request, 5, executeTool);
```

### Pattern 4: Tool Use with Streaming (NEW METHOD)
```zig
var stream = try client.streamWithTools(request, handleToolCalls, handleContent);
defer stream.deinit();
```

## 🛠️ Tool Executor Function

Your tool executor function should have this signature:

```zig
fn executeTool(
    tool_name: []const u8,
    arguments: []const u8, 
    allocator: std.mem.Allocator
) []const u8 {
    // Execute your tool and return JSON result
    return "{\"result\": \"success\", \"data\": \"...\"}";
}
```

## 🎛️ Tool Choice Options

- `.auto`: Let model decide when to use tools
- `.none`: Never use tools
- `.required`: Must use at least one tool
- `.function`: Use a specific tool

## 📊 Method Comparison: Old vs New

| Old Method | New Method | Length Reduction | Benefits |
|------------|------------|----------------|-----------|
| `createChatCompletion()` | `chat()` | 80% | Concise, clear |
| `streamChatCompletion()` | `stream()` | 73% | Direct, unambiguous |
| `createChatCompletionWithToolLoop()` | `chatWithTools()` | 63% | Readable, intuitive |
| `createChatCompletionWithToolCallback()` | `streamWithTools()` | 62% | Simpler, clearer |

## 📈 Usage Examples (Updated)

### Simple Chat (New Method)
```zig
const response = try client.chat(request);
const content = response.choices[0].message.content.?;
```

### Tool Use Loop (New Method)
```zig
const response = try client.chatWithTools(
    request, 
    max_iterations: 5,
    tool_executor: executeWeatherTool,
);
```

### Streaming with Tools (New Method)
```zig
var stream = try client.streamWithTools(
    request,
    handleToolCalls,  // Called when tools detected
    handleContent,   // Called for content chunks
);
defer stream.deinit();

while (try stream.next()) |chunk| {
    // Your callbacks handle tools automatically
}
```

## 🚨 Deprecation Warnings

Old methods show warnings:

```zig
// This will warn: "createChatCompletion is deprecated, use chat() instead"
const response = try client.createChatCompletion(request);
```

## 🎯 Migration Guide

### Step 1: Update Method Calls
```zig
// Old
const response = try client.createChatCompletion(request);

// New
const response = try client.chat(request);
```

### Step 2: Update Tool Methods
```zig
// Old
const response = try client.createChatCompletionWithToolLoop(request, 5, execute);

// New  
const response = try client.chatWithTools(request, 5, execute);
```

### Step 3: Update Streaming Methods
```zig
// Old
var stream = try client.streamChatCompletionWithToolCallback(request, handleTools, handleContent);

// New
var stream = try client.streamWithTools(request, handleTools, handleContent);
```

## ✅ Benefits of New Method Names

### 🎯 Conciseness:
- `chat()` - 4 chars vs 20 chars (80% reduction)
- `stream()` - 6 chars vs 22 chars (73% reduction)
- `chatWithTools()` - 12 chars vs 32 chars (63% reduction)
- `streamWithTools()` - 14 chars vs 37 chars (62% reduction)

### 🔍 Clarity:
- Action-oriented naming (`chat`, `stream`)
- Self-documenting (`chatWithTools`)
- Consistent verb-first pattern
- Reduced cognitive load

### 🏗️ Professionalism:
- Modern API design principles
- Better developer experience
- Easier to type and remember
- Follows industry best practices

## 🎉 Summary

**The library now has modern, concise method names:**

### ✅ Core Methods:
- `chat()` - Non-streaming completion
- `stream()` - Streaming completion  
- `chatWithTools()` - Automatic tool use loop
- `streamWithTools()` - Streaming with tool callbacks

### ✅ Backward Compatibility:
- Old methods still work with deprecation warnings
- Smooth migration path
- No breaking changes

### ✅ Developer Experience:
- Significantly shorter method names
- Clearer intent and functionality
- Consistent naming patterns
- Better code readability

**The API is now modern, concise, and developer-friendly!** 🚀