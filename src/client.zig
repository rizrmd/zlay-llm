const std = @import("std");
const http = @import("http.zig");
const models = @import("models.zig");
const harmony = @import("harmony.zig");
const harmony_parser_mod = @import("harmony_parser.zig");

/// Main LLM client with OpenAI compatibility and Harmony encoding support
pub const LLMClient = struct {
    allocator: std.mem.Allocator,
    http_client: http.HttpClient,
    json_parser: http.JsonParser,
    model: []const u8,
    use_harmony: bool,

    pub const Error = http.Error || error{InvalidHarmonyFormat};

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8, model: []const u8, options: ClientOptions) LLMClient {
        return LLMClient{
            .allocator = allocator,
            .http_client = http.HttpClient.init(allocator, api_key, options.base_url),
            .json_parser = http.JsonParser.init(allocator),
            .model = model,
            .use_harmony = options.use_harmony,
        };
    }

    pub fn deinit(self: *LLMClient) void {
        self.http_client.deinit();
    }

    /// Create a chat completion (non-streaming)
    pub fn createChatCompletion(self: *LLMClient, request: models.ChatCompletionRequest) !models.ChatCompletionResponse {
        if (self.use_harmony) {
            return self.createHarmonyChatCompletion(request);
        } else {
            return self.createStandardChatCompletion(request);
        }
    }

    /// Create a streaming chat completion
    pub fn streamChatCompletion(self: *LLMClient, request: models.ChatCompletionRequest) !ChatCompletionStream {
        if (self.use_harmony) {
            return self.streamHarmonyChatCompletion(request);
        } else {
            return self.streamStandardChatCompletion(request);
        }
    }

    /// Standard OpenAI chat completion
    fn createStandardChatCompletion(self: *LLMClient, request: models.ChatCompletionRequest) !models.ChatCompletionResponse {
        // Simple JSON string for testing
        const request_json = try std.fmt.allocPrint(self.allocator, "{{\"model\":\"{s}\",\"messages\":[{{\"role\":\"{s}\",\"content\":\"{s}\"}}],\"stream\":{s}}}", .{ request.model, request.messages[0].role, request.messages[0].content orelse "", if (request.stream) "true" else "false" });
        defer self.allocator.free(request_json);

        const response_body = try self.http_client.post("/chat/completions", request_json);
        defer self.allocator.free(response_body);

        return self.json_parser.parseChatCompletion(response_body);
    }

    /// Harmony format chat completion
    fn createHarmonyChatCompletion(self: *LLMClient, request: models.ChatCompletionRequest) !models.ChatCompletionResponse {
        // Convert OpenAI messages to Harmony format
        const harmony_messages = try self.convertToHarmonyMessages(request.messages);
        defer {
            for (harmony_messages) |msg| {
                self.allocator.free(msg.content);
            }
            self.allocator.free(harmony_messages);
        }

        const conversation = models.Conversation.init(self.allocator, harmony_messages);
        const prompt = try conversation.renderForCompletion(.assistant);
        defer self.allocator.free(prompt);

        // Create a simple completion request with Harmony prompt
        const completion_request = .{
            .model = self.model,
            .prompt = prompt,
            .max_tokens = request.max_tokens orelse 2048,
            .temperature = request.temperature orelse 0.7,
            .stream = false,
        };

        // Simple JSON string for completion request
        const request_json = try std.fmt.allocPrint(self.allocator, "{{\"model\":\"{s}\",\"prompt\":\"{s}\",\"max_tokens\":{},\"temperature\":{d:.1},\"stream\":{s}}}", .{ completion_request.model, completion_request.prompt, completion_request.max_tokens, completion_request.temperature, if (completion_request.stream) "true" else "false" });
        defer self.allocator.free(request_json);

        const response_body = try self.http_client.post("/completions", request_json);
        defer self.allocator.free(response_body);

        // Parse completion response and convert back to chat format
        return self.convertCompletionToChat(response_body, request.messages);
    }

    /// Standard streaming chat completion
    fn streamStandardChatCompletion(self: *LLMClient, request: models.ChatCompletionRequest) !ChatCompletionStream {
        var stream_request = request;
        stream_request.stream = true;

        // Simple JSON string for streaming request
        const request_json = try std.fmt.allocPrint(self.allocator, "{{\"model\":\"{s}\",\"messages\":[{{\"role\":\"{s}\",\"content\":\"{s}\"}}],\"stream\":{s}}}", .{ stream_request.model, stream_request.messages[0].role, stream_request.messages[0].content orelse "", if (stream_request.stream) "true" else "false" });
        defer self.allocator.free(request_json);

        const http_stream = try self.http_client.postStream("/chat/completions", request_json);

        return ChatCompletionStream{
            .allocator = self.allocator,
            .http_stream = http_stream,
            .json_parser = self.json_parser,
            .use_harmony = false,
            .harmony_parser = null,
        };
    }

    /// Harmony streaming chat completion
    fn streamHarmonyChatCompletion(self: *LLMClient, request: models.ChatCompletionRequest) !ChatCompletionStream {
        // Convert OpenAI messages to Harmony format
        const harmony_messages = try self.convertToHarmonyMessages(request.messages);
        defer {
            for (harmony_messages) |msg| {
                self.allocator.free(msg.content);
            }
            self.allocator.free(harmony_messages);
        }

        const conversation = models.Conversation.init(self.allocator, harmony_messages);
        const prompt = try conversation.renderForCompletion(.assistant);
        defer self.allocator.free(prompt);

        // Create streaming completion request
        const completion_request = .{
            .model = self.model,
            .prompt = prompt,
            .max_tokens = request.max_tokens orelse 2048,
            .temperature = request.temperature orelse 0.7,
            .stream = true,
        };

        // Simple JSON string for streaming completion request
        const request_json = try std.fmt.allocPrint(self.allocator, "{{\"model\":\"{s}\",\"prompt\":\"{s}\",\"max_tokens\":{},\"temperature\":{d:.1},\"stream\":{s}}}", .{ completion_request.model, completion_request.prompt, completion_request.max_tokens, completion_request.temperature, if (completion_request.stream) "true" else "false" });
        defer self.allocator.free(request_json);

        const http_stream = try self.http_client.postStream("/completions", request_json);

        // Initialize Harmony parser
        const harmony_parser = try self.allocator.create(harmony_parser_mod.StreamableParser);
        harmony_parser.* = harmony_parser_mod.StreamableParser.init(self.allocator, .assistant);

        return ChatCompletionStream{
            .allocator = self.allocator,
            .http_stream = http_stream,
            .json_parser = self.json_parser,
            .use_harmony = true,
            .harmony_parser = harmony_parser,
        };
    }

    /// Convert OpenAI messages to Harmony format
    fn convertToHarmonyMessages(self: LLMClient, messages: []const models.ChatMessage) ![]harmony.Message {
        const harmony_messages = try self.allocator.alloc(harmony.Message, messages.len);

        for (messages, 0..) |msg, i| {
            const role = harmony.Role.fromString(msg.role) orelse .user;
            const content = msg.content orelse "";

            harmony_messages[i] = harmony.Message.init(self.allocator, role, content);

            // Handle tool calls
            if (msg.tool_calls) |tool_calls| {
                for (tool_calls) |tool_call| {
                    if (std.mem.eql(u8, tool_call.type, "function")) {
                        harmony_messages[i].withChannel(.commentary);
                        harmony_messages[i].withRecipient(tool_call.function.name);
                        harmony_messages[i].withContentType("json");
                        harmony_messages[i].content = tool_call.function.arguments;
                        break;
                    }
                }
            }

            // Handle tool responses
            if (msg.tool_call_id) |tool_id| {
                harmony_messages[i].header.role = .tool;
                harmony_messages[i].header.recipient = tool_id;
                harmony_messages[i].withChannel(.commentary);
            }
        }

        return harmony_messages;
    }

    /// Convert completion response back to chat format
    fn convertCompletionToChat(self: LLMClient, completion_response: []const u8, original_messages: []const models.ChatMessage) !models.ChatCompletionResponse {

        // Parse completion response
        const parsed = try std.json.parseFromSlice(struct {
            id: []const u8,
            created: u64,
            model: []const u8,
            choices: []const struct {
                text: []const u8,
                finish_reason: ?[]const u8,
            },
            usage: struct {
                prompt_tokens: u32,
                completion_tokens: u32,
                total_tokens: u32,
            },
        }, self.allocator, completion_response, .{});
        defer parsed.deinit();

        // Convert to chat completion format
        const choice = parsed.value.choices[0];

        var messages = try self.allocator.alloc(models.ChatMessage, original_messages.len + 1);
        for (original_messages, 0..) |msg, i| {
            messages[i] = msg;
        }
        messages[messages.len - 1] = .{
            .role = "assistant",
            .content = choice.text,
        };

        const choices = try self.allocator.alloc(models.ChatCompletionResponse.Choice, 1);
        choices[0] = .{
            .index = 0,
            .message = messages[messages.len - 1],
            .finish_reason = choice.finish_reason,
        };

        return models.ChatCompletionResponse{
            .id = try self.allocator.dupe(u8, parsed.value.id),
            .created = parsed.value.created,
            .model = try self.allocator.dupe(u8, parsed.value.model),
            .choices = choices,
            .usage = .{
                .prompt_tokens = parsed.value.usage.prompt_tokens,
                .completion_tokens = parsed.value.usage.completion_tokens,
                .total_tokens = parsed.value.usage.total_tokens,
            },
        };
    }
};

/// Configuration options for the client
pub const ClientOptions = struct {
    base_url: ?[]const u8 = null,
    use_harmony: bool = false,
    timeout_seconds: u32 = 60,
};

/// Simple JSON serialization helper
fn serializeRequest(self: LLMClient, request: models.ChatCompletionRequest) ![]const u8 {
    // For now, return a simple JSON string
    // In a real implementation, you'd use proper JSON serialization
    const json_str = try std.fmt.allocPrint(self.allocator, "{{\"model\":\"{s}\",\"messages\":[{{\"role\":\"user\",\"content\":\"{s}\"}}],\"stream\":{s}}}", .{ request.model, request.messages[0].content, if (request.stream) "true" else "false" });
    return json_str;
}

/// Streaming chat completion iterator
pub const ChatCompletionStream = struct {
    allocator: std.mem.Allocator,
    http_stream: http.StreamIterator,
    json_parser: http.JsonParser,
    use_harmony: bool,
    harmony_parser: ?*harmony_parser_mod.StreamableParser,

    pub fn next(self: *ChatCompletionStream) !?StreamChunk {
        if (self.use_harmony) {
            return self.nextHarmonyChunk();
        } else {
            return self.nextStandardChunk();
        }
    }

    fn nextStandardChunk(self: *ChatCompletionStream) !?StreamChunk {
        const data = try self.http_stream.next() orelse return null;
        defer self.allocator.free(data);

        const chunk = try self.json_parser.parseChatCompletionChunk(data);

        if (chunk.choices.len > 0) {
            const choice = chunk.choices[0];
            return StreamChunk{
                .content = choice.delta.content,
                .role = choice.delta.role,
                .finish_reason = choice.finish_reason,
                .tool_calls = null,
            };
        }

        return null;
    }

    fn nextHarmonyChunk(self: *ChatCompletionStream) !?StreamChunk {
        const data = try self.http_stream.next() orelse return null;
        defer self.allocator.free(data);

        // Parse completion chunk
        const parsed = try std.json.parseFromSlice(struct {
            choices: []const struct {
                text: []const u8,
                finish_reason: ?[]const u8,
            },
        }, self.allocator, data, .{});
        defer parsed.deinit();

        if (parsed.value.choices.len == 0) return null;

        const choice = parsed.value.choices[0];

        // Process tokens through Harmony parser
        var parser = self.harmony_parser.?;

        // Convert text to tokens (simplified - in practice you'd need proper tokenization)
        for (choice.text) |char| {
            const event = try parser.process(@intCast(char));
            if (event) |ev| {
                switch (ev) {
                    .content_delta => |delta| {
                        return StreamChunk{
                            .content = delta,
                            .role = "assistant",
                            .finish_reason = null,
                            .tool_calls = null,
                        };
                    },
                    .message_complete => |msg| {
                        return StreamChunk{
                            .content = msg.content,
                            .role = msg.header.role.toString(),
                            .finish_reason = null,
                            .tool_calls = null,
                        };
                    },
                    .stream_complete => |token| {
                        const finish_reason = if (token == harmony.SpecialToken.return_token) "stop" else "function_call";
                        return StreamChunk{
                            .content = "",
                            .role = null,
                            .finish_reason = finish_reason,
                            .tool_calls = null,
                        };
                    },
                }
            }
        }

        return null;
    }

    pub fn deinit(self: *ChatCompletionStream) void {
        self.http_stream.deinit();
        if (self.harmony_parser) |parser| {
            parser.deinit();
            self.allocator.destroy(parser);
        }
    }
};

/// Individual chunk from a streaming response
pub const StreamChunk = struct {
    content: ?[]const u8,
    role: ?[]const u8,
    finish_reason: ?[]const u8,
    tool_calls: ?[]const models.ChatCompletionChunk.StreamToolCall,
};

test "client initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var client = LLMClient.init(allocator, "test-key", "gpt-4", .{});
    defer client.deinit();

    try testing.expect(std.mem.eql(u8, client.model, "gpt-4"));
    try testing.expect(!client.use_harmony);
}

test "harmony client initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var client = LLMClient.init(allocator, "test-key", "gpt-oss", .{ .use_harmony = true });
    defer client.deinit();

    try testing.expect(std.mem.eql(u8, client.model, "gpt-oss"));
    try testing.expect(client.use_harmony);
}
