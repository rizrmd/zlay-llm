const std = @import("std");
const harmony = @import("harmony.zig");

/// OpenAI-compatible chat completion request
pub const ChatCompletionRequest = struct {
    model: []const u8,
    messages: []const ChatMessage,
    max_tokens: ?u32 = null,
    temperature: ?f32 = null,
    top_p: ?f32 = null,
    frequency_penalty: ?f32 = null,
    presence_penalty: ?f32 = null,
    stop: ?StopTokens = null,
    stream: bool = false,
    tools: ?[]const Tool = null,
    tool_choice: ?ToolChoice = null,
    response_format: ?ResponseFormat = null,

    pub const StopTokens = union(enum) {
        string: []const u8,
        array: []const []const u8,
    };

    pub const Tool = struct {
        type: []const u8 = "function",
        function: ToolFunction,
    };

    pub const ToolFunction = struct {
        name: []const u8,
        description: []const u8,
        parameters: std.json.Value,
    };

    pub const ToolChoice = union(enum) {
        none: void,
        auto: void,
        required: void,
        function: ToolFunctionChoice,
    };

    pub const ToolFunctionChoice = struct {
        name: []const u8,
    };

    pub const ResponseFormat = struct {
        type: []const u8,
        schema: ?std.json.Value = null,
    };
};

/// OpenAI-compatible chat message
pub const ChatMessage = struct {
    role: []const u8,
    content: ?[]const u8 = null,
    tool_calls: ?[]ToolCall = null,
    tool_call_id: ?[]const u8 = null,

    pub const ToolCall = struct {
        id: []const u8,
        type: []const u8 = "function",
        function: ToolCallFunction,
    };

    pub const ToolCallFunction = struct {
        name: []const u8,
        arguments: []const u8,
    };
};

/// OpenAI-compatible chat completion response
pub const ChatCompletionResponse = struct {
    id: []const u8,
    object: []const u8 = "chat.completion",
    created: u64,
    model: []const u8,
    choices: []Choice,
    usage: Usage,

    pub const Choice = struct {
        index: u32,
        message: ChatMessage,
        finish_reason: ?[]const u8 = null,
    };

    pub const Usage = struct {
        prompt_tokens: u32,
        completion_tokens: u32,
        total_tokens: u32,
    };
};

/// Streaming chat completion chunk
pub const ChatCompletionChunk = struct {
    id: []const u8,
    object: []const u8 = "chat.completion.chunk",
    created: u64,
    model: []const u8,
    choices: []StreamChoice,

    pub const StreamChoice = struct {
        index: u32,
        delta: StreamDelta,
        finish_reason: ?[]const u8 = null,
    };

    pub const StreamDelta = struct {
        role: ?[]const u8 = null,
        content: ?[]const u8 = null,
        tool_calls: ?[]StreamToolCall = null,
    };

    pub const StreamToolCall = struct {
        index: u32,
        id: ?[]const u8 = null,
        type: ?[]const u8 = null,
        function: StreamToolCallFunction,
    };

    pub const StreamToolCallFunction = struct {
        name: ?[]const u8 = null,
        arguments: ?[]const u8 = null,
    };
};

/// Harmony-specific conversation structure
pub const Conversation = struct {
    messages: []const harmony.Message,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, messages: []const harmony.Message) Conversation {
        return Conversation{
            .messages = messages,
            .allocator = allocator,
        };
    }

    pub fn addMessage(self: *Conversation, message: harmony.Message) !void {
        const new_messages = try self.allocator.alloc(harmony.Message, self.messages.len + 1);
        std.mem.copy(harmony.Message, new_messages, self.messages);
        new_messages[self.messages.len] = message;

        if (self.messages.len > 0) {
            self.allocator.free(self.messages);
        }

        self.messages = new_messages;
    }

    pub fn renderForCompletion(self: Conversation, target_role: harmony.Role) ![]const u8 {
        // Calculate total size needed
        var total_size: usize = 0;
        for (self.messages) |msg| {
            const rendered = try msg.render();
            defer self.allocator.free(rendered);
            total_size += rendered.len;
        }
        total_size += "<|start|>".len + target_role.toString().len;

        const result = try self.allocator.alloc(u8, total_size);
        var offset: usize = 0;

        // Render all messages
        for (self.messages) |msg| {
            const rendered = try msg.render();
            defer self.allocator.free(rendered);
            @memcpy(result[offset .. offset + rendered.len], rendered);
            offset += rendered.len;
        }

        // Add the start of the target role message
        const start_token = "<|start|>";
        @memcpy(result[offset .. offset + start_token.len], start_token);
        offset += start_token.len;
        const role_str = target_role.toString();
        @memcpy(result[offset .. offset + role_str.len], role_str);

        return result;
    }
};

/// Developer message content for Harmony format
pub const DeveloperContent = struct {
    instructions: []const u8,
    function_tools: ?[]const ToolDescription = null,
    response_formats: ?[]ResponseFormatDescription = null,

    pub const ToolDescription = struct {
        name: []const u8,
        description: []const u8,
        parameters: std.json.Value,
    };

    pub const ResponseFormatDescription = struct {
        name: []const u8,
        description: ?[]const u8 = null,
        schema: std.json.Value,
    };

    pub fn new(instructions: []const u8) DeveloperContent {
        return DeveloperContent{
            .instructions = instructions,
        };
    }

    pub fn withFunctionTools(self: *DeveloperContent, tools: []const ToolDescription) void {
        self.function_tools = tools;
    }

    pub fn withResponseFormats(self: *DeveloperContent, formats: []ResponseFormatDescription) void {
        self.response_formats = formats;
    }

    pub fn render(self: DeveloperContent, allocator: std.mem.Allocator) ![]const u8 {
        // Calculate total size needed
        var total_size = "# Instructions\n\n".len + self.instructions.len + 1;

        if (self.function_tools) |tools| {
            total_size += "\n# Tools\n\n## functions\n\n".len;
            total_size += "namespace functions {\n\n".len;

            for (tools) |tool| {
                total_size += "// ".len + tool.description.len + 1;
                total_size += "type ".len + tool.name.len + " = ".len;
                // Simplified parameter size calculation
                total_size += 50; // placeholder for parameters
                total_size += " => any;\n\n".len;
            }

            total_size += "} // namespace functions".len;
        }

        if (self.response_formats) |formats| {
            total_size += "\n# Response Formats\n\n".len;

            for (formats) |format| {
                total_size += "## ".len + format.name.len + 1;

                if (format.description) |desc| {
                    total_size += "// ".len + desc.len + 1;
                }

                // Simplified JSON schema size calculation
                total_size += 100; // placeholder for schema
                total_size += 1; // newline
            }
        }

        total_size += "<|end|>".len;

        const result = try allocator.alloc(u8, total_size);
        var offset: usize = 0;

        // Instructions
        const inst_header = "# Instructions\n\n";
        @memcpy(result[offset .. offset + inst_header.len], inst_header);
        offset += inst_header.len;
        @memcpy(result[offset .. offset + self.instructions.len], self.instructions);
        offset += self.instructions.len;
        result[offset] = '\n';
        offset += 1;

        // Function tools
        if (self.function_tools) |tools| {
            const tools_header = "\n# Tools\n\n## functions\n\n";
            @memcpy(result[offset .. offset + tools_header.len], tools_header);
            offset += tools_header.len;

            const ns_start = "namespace functions {\n\n";
            @memcpy(result[offset .. offset + ns_start.len], ns_start);
            offset += ns_start.len;

            for (tools) |tool| {
                const comment = "// ";
                @memcpy(result[offset .. offset + comment.len], comment);
                offset += comment.len;
                @memcpy(result[offset .. offset + tool.description.len], tool.description);
                offset += tool.description.len;
                result[offset] = '\n';
                offset += 1;

                const type_start = "type ";
                @memcpy(result[offset .. offset + type_start.len], type_start);
                offset += type_start.len;
                @memcpy(result[offset .. offset + tool.name.len], tool.name);
                offset += tool.name.len;

                const type_mid = " = (_: { location: string }) => any";
                @memcpy(result[offset .. offset + type_mid.len], type_mid);
                offset += type_mid.len;

                const type_end = " => any;\n\n";
                @memcpy(result[offset .. offset + type_end.len], type_end);
                offset += type_end.len;
            }

            const ns_end = "} // namespace functions";
            @memcpy(result[offset .. offset + ns_end.len], ns_end);
            offset += ns_end.len;
        }

        // Response formats
        if (self.response_formats) |formats| {
            const rf_header = "\n# Response Formats\n\n";
            @memcpy(result[offset .. offset + rf_header.len], rf_header);
            offset += rf_header.len;

            for (formats) |format| {
                const fmt_start = "## ";
                @memcpy(result[offset .. offset + fmt_start.len], fmt_start);
                offset += fmt_start.len;
                @memcpy(result[offset .. offset + format.name.len], format.name);
                offset += format.name.len;
                result[offset] = '\n';
                offset += 1;

                if (format.description) |desc| {
                    const desc_start = "// ";
                    @memcpy(result[offset .. offset + desc_start.len], desc_start);
                    offset += desc_start.len;
                    @memcpy(result[offset .. offset + desc.len], desc);
                    offset += desc.len;
                    result[offset] = '\n';
                    offset += 1;
                }

                // Simplified JSON schema
                const schema = "{\"type\":\"object\"}";
                @memcpy(result[offset .. offset + schema.len], schema);
                offset += schema.len;
                result[offset] = '\n';
                offset += 1;
            }
        }

        // End token
        const end_token = "<|end|>";
        @memcpy(result[offset .. offset + end_token.len], end_token);

        return result;
    }

    fn renderParameters(self: DeveloperContent, params: std.json.Value, buffer: *std.ArrayList(u8)) !void {
        _ = self;
        _ = buffer;
        _ = params;
        // Simplified parameter rendering
    }

    fn renderJsonSchema(self: DeveloperContent, schema: std.json.Value, buffer: *std.ArrayList(u8)) !void {
        _ = self;
        _ = buffer;
        _ = schema;
        // Simplified JSON schema rendering
    }
};

test "conversation rendering" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const messages = [_]harmony.Message{
        harmony.Message.init(allocator, .user, "Hello"),
    };

    const conv = Conversation.init(allocator, messages[0..]);
    const rendered = try conv.renderForCompletion(.assistant);
    defer allocator.free(rendered);

    try testing.expect(std.mem.indexOf(u8, rendered, "<|start|>user<|message|>Hello<|end|>") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "<|start|>assistant") != null);
}
