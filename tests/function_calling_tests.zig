const std = @import("std");
const testing = std.testing;
const client = @import("client.zig");
const models = @import("models.zig");

test "function calling request structure" {
    const allocator = testing.allocator;

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

    const messages = [_]models.ChatMessage{
        .{ .role = "user", .content = "What's the weather?" },
    };

    const request = models.ChatCompletionRequest{
        .model = "gpt-4",
        .messages = &messages,
        .tools = &tools,
        .tool_choice = .{ .auto = {} },
    };

    try testing.expect(std.mem.eql(u8, request.model, "gpt-4"));
    try testing.expectEqual(@as(usize, 1), request.tools.?.len);
    try testing.expectEqual(@as(usize, 1), request.messages.len);
    try testing.expect(request.tool_choice != null);
}

test "tool call structure" {
    const tool_call = models.ChatMessage.ToolCall{
        .id = "call_123",
        .type = "function",
        .function = .{
            .name = "get_weather",
            .arguments = "{\"location\":\"Tokyo\"}",
        },
    };

    try testing.expect(std.mem.eql(u8, tool_call.id, "call_123"));
    try testing.expect(std.mem.eql(u8, tool_call.type, "function"));
    try testing.expect(std.mem.eql(u8, tool_call.function.name, "get_weather"));
    try testing.expect(std.mem.eql(u8, tool_call.function.arguments, "{\"location\":\"Tokyo\"}"));
}

test "streaming tool call chunk" {
    const tool_call = models.ChatCompletionChunk.StreamToolCall{
        .index = 0,
        .id = "call_123",
        .type = "function",
        .function = .{
            .name = "get_weather",
            .arguments = "{\"location\":",
        },
    };

    try testing.expectEqual(@as(u32, 0), tool_call.index);
    try testing.expect(std.mem.eql(u8, tool_call.id.?, "call_123"));
    try testing.expect(std.mem.eql(u8, tool_call.type.?, "function"));
    try testing.expect(std.mem.eql(u8, tool_call.function.name.?, "get_weather"));
    try testing.expect(std.mem.eql(u8, tool_call.function.arguments.?, "{\"location\":"));
}

test "function calling with harmony format" {
    const allocator = testing.allocator;

    // Test Harmony message with function call
    var msg = @import("harmony.zig").Message.init(allocator, .assistant, "{\"location\":\"Tokyo\"}");
    msg.withChannel(.commentary);
    msg.withRecipient("functions.get_weather");
    msg.withContentType("json");

    const rendered = try msg.render();
    defer allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "to=functions.get_weather") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "<|channel|> commentary") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "<|constrain|> json") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "{\"location\":\"Tokyo\"}") != null);
}

test "developer content with function tools" {
    const allocator = testing.allocator;

    var dev_content = models.DeveloperContent.new("You are a helpful assistant.");

    const tools = [_]models.DeveloperContent.ToolDescription{
        .{
            .name = "get_weather",
            .description = "Get weather information",
            .parameters = std.json.Value{
                .object = std.json.ObjectMap.init(allocator),
            },
        },
    };

    dev_content.withFunctionTools(&tools);

    const rendered = try dev_content.render(allocator);
    defer allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "# Instructions") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "You are a helpful assistant.") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "# Tools") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "namespace functions") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "get_weather") != null);
}

test "tool choice variants" {
    const auto_choice = models.ChatCompletionRequest.ToolChoice{ .auto = {} };
    const none_choice = models.ChatCompletionRequest.ToolChoice{ .none = {} };
    const required_choice = models.ChatCompletionRequest.ToolChoice{ .required = {} };
    const function_choice = models.ChatCompletionRequest.ToolChoice{
        .function = .{ .name = "get_weather" },
    };

    // Test that we can create all variants
    _ = auto_choice;
    _ = none_choice;
    _ = required_choice;
    _ = function_choice;

    try testing.expect(true);
}

test "client with function calling support" {
    const allocator = testing.allocator;

    const client_instance = client.LLMClient.init(allocator, "test-key", "gpt-4", .{});
    defer client_instance.deinit();

    try testing.expect(std.mem.eql(u8, client_instance.model, "gpt-4"));
    try testing.expect(!client_instance.use_harmony);
}

test "harmony client with function calling support" {
    const allocator = testing.allocator;

    const harmony_client = client.LLMClient.init(allocator, "test-key", "gpt-oss", .{ .use_harmony = true });
    defer harmony_client.deinit();

    try testing.expect(std.mem.eql(u8, harmony_client.model, "gpt-oss"));
    try testing.expect(harmony_client.use_harmony);
}
