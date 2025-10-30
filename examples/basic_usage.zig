const std = @import("std");
const client = @import("../src/client.zig");
const models = @import("../src/models.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Initialize the client
    const api_key = std.os.getenv("OPENAI_API_KEY") orelse {
        std.debug.print("Please set OPENAI_API_KEY environment variable\n");
        return;
    };

    // Standard OpenAI client
    var standard_client = client.LLMClient.init(allocator, api_key, "gpt-4", .{});
    defer standard_client.deinit();

    // Harmony-enabled client for gpt-oss models
    var harmony_client = client.LLMClient.init(allocator, api_key, "gpt-oss", .{ .use_harmony = true });
    defer harmony_client.deinit();

    // Example messages
    const messages = [_]models.ChatMessage{
        .{ .role = "system", .content = "You are a helpful assistant." },
        .{ .role = "user", .content = "What is 2 + 2?" },
    };

    // Standard chat completion
    std.debug.print("=== Standard Chat Completion ===\n");
    const request = models.ChatCompletionRequest{
        .model = "gpt-4",
        .messages = &messages,
        .max_tokens = 100,
        .temperature = 0.7,
    };

    const response = try standard_client.createChatCompletion(request);
    defer {
        for (response.choices) |choice| {
            allocator.free(choice.message.content);
        }
        allocator.free(response.choices);
    }

    std.debug.print("Response: {s}\n", .{response.choices[0].message.content.?});
    std.debug.print("Tokens used: {}\n", .{response.usage.total_tokens});

    // Streaming chat completion
    std.debug.print("\n=== Streaming Chat Completion ===\n");
    var stream = try standard_client.streamChatCompletion(request);
    defer stream.deinit();

    while (try stream.next()) |chunk| {
        if (chunk.content.len > 0) {
            std.debug.print("{s}", .{chunk.content});
        }
        if (chunk.finish_reason) |reason| {
            std.debug.print("\nFinish reason: {s}\n", .{reason});
        }
    }

    // Harmony format example (if you have access to gpt-oss models)
    std.debug.print("\n=== Harmony Format Example ===\n");
    var harmony_stream = try harmony_client.streamChatCompletion(request);
    defer harmony_stream.deinit();

    while (try harmony_stream.next()) |chunk| {
        if (chunk.content.len > 0) {
            std.debug.print("{s}", .{chunk.content});
        }
        if (chunk.finish_reason) |reason| {
            std.debug.print("\nFinish reason: {s}\n", .{reason});
        }
    }
}

// Example with function calling
pub fn functionCallingExample() !void {
    const allocator = std.heap.page_allocator;

    const api_key = std.os.getenv("OPENAI_API_KEY") orelse return;

    var client_instance = client.LLMClient.init(allocator, api_key, "gpt-4", .{});
    defer client_instance.deinit();

    const tools = [_]models.ChatCompletionRequest.Tool{
        .{
            .function = .{
                .name = "get_weather",
                .description = "Get the current weather in a location",
                .parameters = std.json.Value{
                    .object = std.json.ObjectMap.init(allocator),
                },
            },
        },
    };

    const messages = [_]models.ChatMessage{
        .{ .role = "user", .content = "What's the weather in Tokyo?" },
    };

    const request = models.ChatCompletionRequest{
        .model = "gpt-4",
        .messages = &messages,
        .tools = &tools,
        .tool_choice = .{ .auto = {} },
    };

    var stream = try client_instance.streamChatCompletion(request);
    defer stream.deinit();

    while (try stream.next()) |chunk| {
        if (chunk.content) |content| {
            if (content.len > 0) {
                std.debug.print("{s}", .{content});
            }
        }

        if (chunk.tool_calls) |tool_calls| {
            for (tool_calls) |tool_call| {
                if (tool_call.function.name) |name| {
                    std.debug.print("\nTool call: {s}\n", .{name});
                }
                if (tool_call.function.arguments) |args| {
                    std.debug.print("Arguments: {s}\n", .{args});
                }
            }
        }

        if (chunk.finish_reason) |reason| {
            std.debug.print("\nFinish reason: {s}\n", .{reason});
        }
    }
}
