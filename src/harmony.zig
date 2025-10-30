const std = @import("std");

/// Special tokens used in OpenAI Harmony format
pub const SpecialToken = struct {
    pub const start: u32 = 200006; // <|start|>
    pub const end: u32 = 200007; // <|end|>
    pub const message: u32 = 200008; // <|message|>
    pub const channel: u32 = 200005; // <|channel|>
    pub const constrain: u32 = 200003; // <|constrain|>
    pub const return_token: u32 = 200002; // <|return|>
    pub const call: u32 = 200012; // <|call|>

    pub fn toString(token: u32) ?[]const u8 {
        return switch (token) {
            start => "<|start|>",
            end => "<|end|>",
            message => "<|message|>",
            channel => "<|channel|>",
            constrain => "<|constrain|>",
            return_token => "<|return|>",
            call => "<|call|>",
            else => null,
        };
    }

    pub fn fromString(str: []const u8) ?u32 {
        if (std.mem.eql(u8, str, "<|start|>")) return start;
        if (std.mem.eql(u8, str, "<|end|>")) return end;
        if (std.mem.eql(u8, str, "<|message|>")) return message;
        if (std.mem.eql(u8, str, "<|channel|>")) return channel;
        if (std.mem.eql(u8, str, "<|constrain|>")) return constrain;
        if (std.mem.eql(u8, str, "<|return|>")) return return_token;
        if (std.mem.eql(u8, str, "<|call|>")) return call;
        return null;
    }
};

/// Message roles in Harmony format
pub const Role = enum {
    system,
    developer,
    user,
    assistant,
    tool,

    pub fn toString(self: Role) []const u8 {
        return switch (self) {
            .system => "system",
            .developer => "developer",
            .user => "user",
            .assistant => "assistant",
            .tool => "tool",
        };
    }

    pub fn fromString(str: []const u8) ?Role {
        if (std.mem.eql(u8, str, "system")) return .system;
        if (std.mem.eql(u8, str, "developer")) return .developer;
        if (std.mem.eql(u8, str, "user")) return .user;
        if (std.mem.eql(u8, str, "assistant")) return .assistant;
        if (std.mem.eql(u8, str, "tool")) return .tool;
        return null;
    }
};

/// Assistant message channels
pub const Channel = enum {
    analysis,
    commentary,
    final,

    pub fn toString(self: Channel) []const u8 {
        return switch (self) {
            .analysis => "analysis",
            .commentary => "commentary",
            .final => "final",
        };
    }

    pub fn fromString(str: []const u8) ?Channel {
        if (std.mem.eql(u8, str, "analysis")) return .analysis;
        if (std.mem.eql(u8, str, "commentary")) return .commentary;
        if (std.mem.eql(u8, str, "final")) return .final;
        return null;
    }
};

/// Reasoning effort levels
pub const ReasoningEffort = enum {
    low,
    medium,
    high,

    pub fn toString(self: ReasoningEffort) []const u8 {
        return switch (self) {
            .low => "low",
            .medium => "medium",
            .high => "high",
        };
    }
};

/// Message header information
pub const MessageHeader = struct {
    role: Role,
    channel: ?Channel = null,
    recipient: ?[]const u8 = null,
    content_type: ?[]const u8 = null,

    pub fn format(self: MessageHeader, allocator: std.mem.Allocator) ![]const u8 {
        // Calculate total size needed
        var total_size = self.role.toString().len;

        if (self.channel) |ch| {
            total_size += 1 + "<|channel|>".len + 1 + ch.toString().len;
        }
        if (self.recipient) |rec| {
            total_size += 1 + "to=".len + rec.len;
        }
        if (self.content_type) |ct| {
            total_size += 1 + "<|constrain|>".len + 1 + ct.len;
        }

        const result = try allocator.alloc(u8, total_size);
        var offset: usize = 0;

        // Role
        const role_str = self.role.toString();
        @memcpy(result[offset .. offset + role_str.len], role_str);
        offset += role_str.len;

        // Channel
        if (self.channel) |ch| {
            result[offset] = ' ';
            offset += 1;
            const channel_token = "<|channel|>";
            @memcpy(result[offset .. offset + channel_token.len], channel_token);
            offset += channel_token.len;
            result[offset] = ' ';
            offset += 1;
            const channel_str = ch.toString();
            @memcpy(result[offset .. offset + channel_str.len], channel_str);
            offset += channel_str.len;
        }

        // Recipient
        if (self.recipient) |rec| {
            result[offset] = ' ';
            offset += 1;
            const to_str = "to=";
            @memcpy(result[offset .. offset + to_str.len], to_str);
            offset += to_str.len;
            @memcpy(result[offset .. offset + rec.len], rec);
            offset += rec.len;
        }

        // Content type
        if (self.content_type) |ct| {
            result[offset] = ' ';
            offset += 1;
            const constrain_token = "<|constrain|>";
            @memcpy(result[offset .. offset + constrain_token.len], constrain_token);
            offset += constrain_token.len;
            result[offset] = ' ';
            offset += 1;
            @memcpy(result[offset .. offset + ct.len], ct);
            offset += ct.len;
        }

        return result;
    }
};

/// Complete Harmony message
pub const Message = struct {
    header: MessageHeader,
    content: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, role: Role, content: []const u8) Message {
        return Message{
            .header = .{ .role = role },
            .content = content,
            .allocator = allocator,
        };
    }

    pub fn withChannel(self: *Message, channel: Channel) void {
        self.header.channel = channel;
    }

    pub fn withRecipient(self: *Message, recipient: []const u8) void {
        self.header.recipient = recipient;
    }

    pub fn withContentType(self: *Message, content_type: []const u8) void {
        self.header.content_type = content_type;
    }

    pub fn render(self: Message) ![]const u8 {
        // Calculate total size needed
        const header_str = try self.header.format(self.allocator);
        defer self.allocator.free(header_str);

        const total_size = "<|start|>".len + header_str.len + "<|message|>".len +
            self.content.len + "<|end|>".len;

        const result = try self.allocator.alloc(u8, total_size);
        var offset: usize = 0;

        @memcpy(result[offset .. offset + "<|start|>".len], "<|start|>");
        offset += "<|start|>".len;

        @memcpy(result[offset .. offset + header_str.len], header_str);
        offset += header_str.len;

        @memcpy(result[offset .. offset + "<|message|>".len], "<|message|>");
        offset += "<|message|>".len;

        @memcpy(result[offset .. offset + self.content.len], self.content);
        offset += self.content.len;

        @memcpy(result[offset .. offset + "<|end|>".len], "<|end|>");

        return result;
    }
};

/// System message content for Harmony format
pub const SystemContent = struct {
    identity: []const u8 = "You are ChatGPT, a large language model trained by OpenAI.",
    knowledge_cutoff: []const u8 = "2024-06",
    current_date: []const u8,
    reasoning: ReasoningEffort = .medium,
    valid_channels: []const []const u8 = &.{ "analysis", "commentary", "final" },
    function_tools: bool = false,
    built_in_tools: ?[]const []const u8 = null,

    pub fn new(current_date: []const u8) SystemContent {
        return SystemContent{
            .current_date = current_date,
        };
    }

    pub fn withReasoningEffort(self: *SystemContent, effort: ReasoningEffort) void {
        self.reasoning = effort;
    }

    pub fn withFunctionTools(self: *SystemContent, enabled: bool) void {
        self.function_tools = enabled;
    }

    pub fn withBuiltInTools(self: *SystemContent, tools: []const []const u8) void {
        self.built_in_tools = tools;
    }

    pub fn render(self: SystemContent, allocator: std.mem.Allocator) ![]const u8 {
        // Calculate total size needed
        var total_size = self.identity.len + 1; // + newline
        total_size += "Knowledge cutoff: ".len + self.knowledge_cutoff.len + 1;
        total_size += "Current date: ".len + self.current_date.len + 2; // +2 newlines
        total_size += "Reasoning: ".len + self.reasoning.toString().len + 2;

        if (self.built_in_tools) |tools| {
            total_size += "# Tools\n\n".len;
            for (tools) |tool| {
                total_size += "## ".len + tool.len + 1;
            }
            total_size += 1; // final newline
        }

        total_size += "# Valid channels: ".len;
        for (self.valid_channels, 0..) |channel, i| {
            if (i > 0) total_size += 2; // ", "
            total_size += channel.len;
        }
        total_size += ". Channel must be included for every message.".len;

        if (self.function_tools) {
            total_size += "\nCalls to these tools must go to the commentary channel: 'functions'.".len;
        }

        total_size += "<|end|>".len;

        const result = try allocator.alloc(u8, total_size);
        var offset: usize = 0;

        // Identity
        @memcpy(result[offset .. offset + self.identity.len], self.identity);
        offset += self.identity.len;
        result[offset] = '\n';
        offset += 1;

        // Knowledge cutoff
        const kc_str = "Knowledge cutoff: ";
        @memcpy(result[offset .. offset + kc_str.len], kc_str);
        offset += kc_str.len;
        @memcpy(result[offset .. offset + self.knowledge_cutoff.len], self.knowledge_cutoff);
        offset += self.knowledge_cutoff.len;
        result[offset] = '\n';
        offset += 1;

        // Current date
        const cd_str = "Current date: ";
        @memcpy(result[offset .. offset + cd_str.len], cd_str);
        offset += cd_str.len;
        @memcpy(result[offset .. offset + self.current_date.len], self.current_date);
        offset += self.current_date.len;
        const nl2 = "\n\n";
        @memcpy(result[offset .. offset + nl2.len], nl2);
        offset += nl2.len;

        // Reasoning
        const re_str = "Reasoning: ";
        @memcpy(result[offset .. offset + re_str.len], re_str);
        offset += re_str.len;
        const reasoning_str = self.reasoning.toString();
        @memcpy(result[offset .. offset + reasoning_str.len], reasoning_str);
        offset += reasoning_str.len;
        @memcpy(result[offset .. offset + nl2.len], nl2);
        offset += nl2.len;

        // Tools
        if (self.built_in_tools) |tools| {
            const tools_header = "# Tools\n\n";
            @memcpy(result[offset .. offset + tools_header.len], tools_header);
            offset += tools_header.len;

            for (tools) |tool| {
                const tool_prefix = "## ";
                @memcpy(result[offset .. offset + tool_prefix.len], tool_prefix);
                offset += tool_prefix.len;
                @memcpy(result[offset .. offset + tool.len], tool);
                offset += tool.len;
                result[offset] = '\n';
                offset += 1;
            }
            result[offset] = '\n';
            offset += 1;
        }

        // Valid channels
        const vc_str = "# Valid channels: ";
        @memcpy(result[offset .. offset + vc_str.len], vc_str);
        offset += vc_str.len;

        for (self.valid_channels, 0..) |channel, i| {
            if (i > 0) {
                result[offset] = ',';
                offset += 1;
                result[offset] = ' ';
                offset += 1;
            }
            @memcpy(result[offset .. offset + channel.len], channel);
            offset += channel.len;
        }

        const vc_suffix = ". Channel must be included for every message.";
        @memcpy(result[offset .. offset + vc_suffix.len], vc_suffix);
        offset += vc_suffix.len;

        // Function tools note
        if (self.function_tools) {
            const ft_note = "\nCalls to these tools must go to the commentary channel: 'functions'.";
            @memcpy(result[offset .. offset + ft_note.len], ft_note);
            offset += ft_note.len;
        }

        // End token
        const end_token = "<|end|>";
        @memcpy(result[offset .. offset + end_token.len], end_token);

        return result;
    }
};

test "special token conversion" {
    const testing = std.testing;

    try testing.expectEqual(SpecialToken.start, 200006);
    try testing.expectEqual(SpecialToken.end, 200007);
    try testing.expectEqual(SpecialToken.message, 200008);

    try testing.expect(std.mem.eql(u8, SpecialToken.toString(SpecialToken.start).?, "<|start|>"));
    try testing.expect(std.mem.eql(u8, SpecialToken.toString(SpecialToken.end).?, "<|end|>"));

    try testing.expectEqual(SpecialToken.fromString("<|start|>").?, SpecialToken.start);
    try testing.expectEqual(SpecialToken.fromString("<|end|>").?, SpecialToken.end);
}

test "role conversion" {
    const testing = std.testing;

    try testing.expect(std.mem.eql(u8, Role.system.toString(), "system"));
    try testing.expect(std.mem.eql(u8, Role.assistant.toString(), "assistant"));

    try testing.expectEqual(Role.fromString("system").?, Role.system);
    try testing.expectEqual(Role.fromString("assistant").?, Role.assistant);
}

test "message rendering" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var msg = Message.init(allocator, .user, "What is 2 + 2?");
    const rendered = try msg.render();
    defer allocator.free(rendered);

    try testing.expect(std.mem.eql(u8, rendered, "<|start|>user<|message|>What is 2 + 2?<|end|>"));
}

test "message with channel and recipient" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var msg = Message.init(allocator, .assistant, "{\"location\":\"Tokyo\"}");
    msg.withChannel(.commentary);
    msg.withRecipient("functions.get_current_weather");
    msg.withContentType("json");

    const rendered = try msg.render();
    defer allocator.free(rendered);

    const expected = "<|start|>assistant <|channel|> commentary to=functions.get_current_weather <|constrain|> json<|message|>{\"location\":\"Tokyo\"}<|end|>";
    try testing.expect(std.mem.eql(u8, rendered, expected));
}
