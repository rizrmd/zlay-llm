const std = @import("std");
const client = @import("../src/client.zig");
const models = @import("../src/models.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const api_key = std.posix.getenv("OPENAI_API_KEY") orelse {
        std.debug.print("Please set OPENAI_API_KEY environment variable\n");
        return;
    };

    var client_instance = client.LLMClient.init(allocator, api_key, "gpt-4", .{});
    defer client_instance.deinit();

    // Define tools for function calling
    const tools = [_]models.ChatCompletionRequest.Tool{
        .{
            .function = .{
                .name = "get_current_weather",
                .description = "Get the current weather in a given location",
                .parameters = std.json.Value{
                    .object = std.json.ObjectMap.init(allocator),
                },
            },
        },
        .{
            .function = .{
                .name = "calculate_sum",
                .description = "Calculate the sum of two numbers",
                .parameters = std.json.Value{
                    .object = std.json.ObjectMap.init(allocator),
                },
            },
        },
    };

    const messages = [_]models.ChatMessage{
        .{ .role = "user", .content = "What's the weather in Tokyo and what's 15 + 27?" },
    };

    const request = models.ChatCompletionRequest{
        .model = "gpt-4",
        .messages = &messages,
        .tools = &tools,
        .tool_choice = .{ .auto = {} },
        .max_tokens = 500,
        .temperature = 0.7,
    };

    std.debug.print("=== Function Calling Example ===\n");
    std.debug.print("User: What's the weather in Tokyo and what's 15 + 27?\n\n");

    // Test streaming with function calling
    var stream = try client_instance.streamChatCompletion(request);
    defer stream.deinit();

    var current_tool_call: ?models.ChatCompletionChunk.StreamToolCall = null;
    var tool_call_index: u32 = 0;

    while (try stream.next()) |chunk| {
        if (chunk.content) |content| {
            if (content.len > 0) {
                std.debug.print("{s}", .{content});
            }
        }

        if (chunk.tool_calls) |tool_calls| {
            for (tool_calls) |tool_call| {
                if (tool_call.index == tool_call_index) {
                    if (current_tool_call == null) {
                        current_tool_call = tool_call;
                        std.debug.print("\n[Tool Call Start]\n");
                    } else {
                        // Update existing tool call
                        if (tool_call.function.name) |name| {
                            std.debug.print("Function: {s}\n", .{name});
                        }
                        if (tool_call.function.arguments) |args| {
                            std.debug.print("Arguments: {s}\n", .{args});
                        }
                    }
                } else {
                    tool_call_index = tool_call.index;
                    current_tool_call = tool_call;
                }
            }
        }

        if (chunk.finish_reason) |reason| {
            std.debug.print("\nFinish reason: {s}\n", .{reason});
        }
    }

    std.debug.print("\n=== Function Calling Test Complete ===\n");
}

// Test Harmony format with function calling
pub fn harmonyFunctionCallingExample() !void {
    const allocator = std.heap.page_allocator;

    const api_key = std.posix.getenv("OPENAI_API_KEY") orelse return;

    var harmony_client = client.LLMClient.init(allocator, api_key, "gpt-oss", .{ .use_harmony = true });
    defer harmony_client.deinit();

    // Create Harmony format messages with function calling
    const messages = [_]models.ChatMessage{
        .{ .role = "system", .content = "You are a helpful assistant with access to weather and calculation tools." },
        .{ .role = "user", .content = "What's the weather in Tokyo?" },
    };

    const tools = [_]models.ChatCompletionRequest.Tool{
        .{
            .function = .{
                .name = "get_weather",
                .description = "Get weather information",
                .parameters = std.json.Value{
                    .object = std.json.ObjectMap.init(allocator),
                },
            },
        },
    };

    const request = models.ChatCompletionRequest{
        .model = "gpt-oss",
        .messages = &messages,
        .tools = &tools,
        .tool_choice = .{ .auto = {} },
    };

    std.debug.print("=== Harmony Function Calling Example ===\n");

    var stream = try harmony_client.streamChatCompletion(request);
    defer stream.deinit();

    while (try stream.next()) |chunk| {
        if (chunk.content) |content| {
            if (content.len > 0) {
                std.debug.print("{s}", .{content});
            }
        }

        if (chunk.tool_calls) |tool_calls| {
            for (tool_calls) |tool_call| {
                std.debug.print("\n[Harmony Tool Call]\n");
                if (tool_call.function.name) |name| {
                    std.debug.print("Function: {s}\n", .{name});
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
