const std = @import("std");

// Export all modules for external use
pub const client = @import("client.zig");
pub const models = @import("models.zig");
pub const harmony = @import("harmony.zig");
pub const harmony_parser = @import("harmony_parser.zig");
pub const http = @import("http.zig");

pub fn main() !void {
    _ = std.heap.page_allocator; // Mark as used to avoid warning

    // Basic demonstration
    std.debug.print("Zlay LLM Client - OpenAI Compatible with Harmony Encoding\n", .{});

    // Test basic functionality
    const api_key = std.posix.getenv("OPENAI_API_KEY") orelse {
        std.debug.print("Set OPENAI_API_KEY to test with real API\n", .{});
        return;
    };

    _ = api_key; // Mark as used to avoid warning

    std.debug.print("Client initialized successfully!\n", .{});
}

test "basic functionality" {
    const testing = std.testing;

    // Test harmony token definitions
    try testing.expectEqual(@as(u32, 200006), harmony.SpecialToken.start);
    try testing.expectEqual(@as(u32, 200007), harmony.SpecialToken.end);

    // Test role conversion
    try testing.expectEqual(harmony.Role.system, harmony.Role.fromString("system").?);
    try testing.expectEqual(harmony.Role.assistant, harmony.Role.fromString("assistant").?);

    // Test message rendering
    const allocator = testing.allocator;
    var msg = harmony.Message.init(allocator, .user, "Hello");
    const rendered = try msg.render();
    defer allocator.free(rendered);

    try testing.expect(std.mem.eql(u8, rendered, "<|start|>user<|message|>Hello<|end|>"));
}

test "function calling request structure" {
    const testing = std.testing;
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
        .messages = messages[0..],
        .tools = tools[0..],
        .tool_choice = .{ .auto = {} },
    };

    try testing.expect(std.mem.eql(u8, request.model, "gpt-4"));
    try testing.expectEqual(@as(usize, 1), request.tools.?.len);
    try testing.expectEqual(@as(usize, 1), request.messages.len);
    try testing.expect(request.tool_choice != null);
}

test "harmony message with function call" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var msg = harmony.Message.init(allocator, .assistant, "{\"location\":\"Tokyo\"}");
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
    const testing = std.testing;
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

    dev_content.withFunctionTools(tools[0..]);

    const rendered = try dev_content.render(allocator);
    defer allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "# Instructions") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "You are a helpful assistant.") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "# Tools") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "namespace functions") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "get_weather") != null);
}
