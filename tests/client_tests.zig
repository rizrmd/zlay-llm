const std = @import("std");
const testing = std.testing;
const client = @import("../src/client.zig");
const models = @import("../src/models.zig");
const harmony = @import("../src/harmony.zig");
const harmony_parser = @import("../src/harmony_parser.zig");

test "harmony special tokens" {
    try testing.expectEqual(@as(u32, 200006), harmony.SpecialToken.start);
    try testing.expectEqual(@as(u32, 200007), harmony.SpecialToken.end);
    try testing.expectEqual(@as(u32, 200008), harmony.SpecialToken.message);
    try testing.expectEqual(@as(u32, 200005), harmony.SpecialToken.channel);
    try testing.expectEqual(@as(u32, 200003), harmony.SpecialToken.constrain);
    try testing.expectEqual(@as(u32, 200002), harmony.SpecialToken.return_token);
    try testing.expectEqual(@as(u32, 200012), harmony.SpecialToken.call);
}

test "harmony role conversion" {
    try testing.expectEqual(harmony.Role.system, harmony.Role.fromString("system").?);
    try testing.expectEqual(harmony.Role.developer, harmony.Role.fromString("developer").?);
    try testing.expectEqual(harmony.Role.user, harmony.Role.fromString("user").?);
    try testing.expectEqual(harmony.Role.assistant, harmony.Role.fromString("assistant").?);
    try testing.expectEqual(harmony.Role.tool, harmony.Role.fromString("tool").?);

    try testing.expect(harmony.Role.fromString("invalid") == null);
}

test "harmony channel conversion" {
    try testing.expectEqual(harmony.Channel.analysis, harmony.Channel.fromString("analysis").?);
    try testing.expectEqual(harmony.Channel.commentary, harmony.Channel.fromString("commentary").?);
    try testing.expectEqual(harmony.Channel.final, harmony.Channel.fromString("final").?);

    try testing.expect(harmony.Channel.fromString("invalid") == null);
}

test "harmony message rendering" {
    const allocator = testing.allocator;

    var msg = harmony.Message.init(allocator, .user, "Hello, world!");
    const rendered = try msg.render();
    defer allocator.free(rendered);

    try testing.expect(std.mem.eql(u8, rendered, "<|start|>user<|message|>Hello, world!<|end|>"));
}

test "harmony message with channel" {
    const allocator = testing.allocator;

    var msg = harmony.Message.init(allocator, .assistant, "I am thinking...");
    msg.withChannel(.analysis);

    const rendered = try msg.render();
    defer allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "<|channel|>analysis") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "I am thinking...") != null);
}

test "harmony message with recipient and content type" {
    const allocator = testing.allocator;

    var msg = harmony.Message.init(allocator, .assistant, "{\"location\":\"Tokyo\"}");
    msg.withChannel(.commentary);
    msg.withRecipient("functions.get_weather");
    msg.withContentType("json");

    const rendered = try msg.render();
    defer allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "to=functions.get_weather") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "<|constrain|> json") != null);
}

test "system content rendering" {
    const allocator = testing.allocator;

    var sys_content = harmony.SystemContent.new("2025-01-30");
    sys_content.withReasoningEffort(.high);

    const rendered = try sys_content.render(allocator);
    defer allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "You are ChatGPT") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Knowledge cutoff: 2024-06") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Current date: 2025-01-30") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "Reasoning: high") != null);
}

test "developer content rendering" {
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
}

test "conversation rendering" {
    const allocator = testing.allocator;

    const messages = [_]harmony.Message{
        harmony.Message.init(allocator, .system, "You are helpful."),
        harmony.Message.init(allocator, .user, "Hello!"),
    };

    const conv = models.Conversation.init(allocator, &messages);
    const rendered = try conv.renderForCompletion(.assistant);
    defer allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "<|start|>system<|message|>You are helpful.<|end|>") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "<|start|>user<|message|>Hello!<|end|>") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "<|start|>assistant") != null);
}

test "harmony streaming parser basic" {
    const allocator = testing.allocator;

    var parser = harmony_parser.StreamableParser.init(allocator, .assistant);
    defer parser.deinit();

    // Simulate: <|start|>assistant<|message|>Hello<|end|>
    const tokens = [_]u32{
        harmony.SpecialToken.start,
        'a',
        's',
        's',
        'i',
        's',
        't',
        'a',
        'n',
        't',
        harmony.SpecialToken.message,
        'H',
        'e',
        'l',
        'l',
        'o',
        harmony.SpecialToken.end,
    };

    var message_count: usize = 0;
    for (tokens) |token| {
        const event = try parser.process(token);
        if (event) |ev| {
            switch (ev) {
                .message_complete => {
                    message_count += 1;
                },
                else => {},
            }
        }
    }

    try testing.expectEqual(@as(usize, 1), message_count);
}

test "harmony streaming parser with return token" {
    const allocator = testing.allocator;

    var parser = harmony_parser.StreamableParser.init(allocator, .assistant);
    defer parser.deinit();

    // Simulate: <|start|>assistant<|message|>Hello<|return|>
    const tokens = [_]u32{
        harmony.SpecialToken.start,
        'a',
        's',
        's',
        'i',
        's',
        't',
        'a',
        'n',
        't',
        harmony.SpecialToken.message,
        'H',
        'e',
        'l',
        'l',
        'o',
        harmony.SpecialToken.return_token,
    };

    var stream_complete = false;
    for (tokens) |token| {
        const event = try parser.process(token);
        if (event) |ev| {
            switch (ev) {
                .stream_complete => {
                    stream_complete = true;
                    try testing.expectEqual(harmony.SpecialToken.return_token, ev.stream_complete);
                },
                else => {},
            }
        }
    }

    try testing.expect(stream_complete);
}

test "client initialization" {
    const allocator = testing.allocator;

    const client_instance = client.LLMClient.init(allocator, "test-key", "gpt-4", .{});
    defer client_instance.deinit();

    try testing.expect(std.mem.eql(u8, client_instance.model, "gpt-4"));
    try testing.expect(!client_instance.use_harmony);
}

test "harmony client initialization" {
    const allocator = testing.allocator;

    const client_instance = client.LLMClient.init(allocator, "test-key", "gpt-oss", .{ .use_harmony = true });
    defer client_instance.deinit();

    try testing.expect(std.mem.eql(u8, client_instance.model, "gpt-oss"));
    try testing.expect(client_instance.use_harmony);
}

test "openai message structure" {
    const message = models.ChatMessage{
        .role = "user",
        .content = "Hello, world!",
        .tool_calls = null,
        .tool_call_id = null,
    };

    try testing.expect(std.mem.eql(u8, message.role, "user"));
    try testing.expect(std.mem.eql(u8, message.content.?, "Hello, world!"));
}

test "openai request structure" {
    const messages = [_]models.ChatMessage{
        .{ .role = "user", .content = "Hello" },
    };

    const request = models.ChatCompletionRequest{
        .model = "gpt-4",
        .messages = &messages,
        .max_tokens = 100,
        .temperature = 0.7,
        .stream = false,
    };

    try testing.expect(std.mem.eql(u8, request.model, "gpt-4"));
    try testing.expectEqual(@as(u32, 100), request.max_tokens.?);
    try testing.expectEqual(@as(f32, 0.7), request.temperature.?);
    try testing.expect(!request.stream);
}
