const std = @import("std");
const models = @import("models.zig");

/// HTTP client for OpenAI API with streaming support
pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    base_url: []const u8,
    client: std.http.Client,

    pub const Error = error{
        NetworkError,
        InvalidResponse,
        AuthenticationError,
        RateLimitError,
        InvalidRequest,
        ServerError,
        JsonParseError,
    };

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8, base_url: ?[]const u8) HttpClient {
        return HttpClient{
            .allocator = allocator,
            .api_key = api_key,
            .base_url = base_url orelse "https://api.openai.com/v1",
            .client = std.http.Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *HttpClient) void {
        self.client.deinit();
    }

    /// Make a non-streaming POST request
    pub fn post(self: *HttpClient, path: []const u8, request_body: []const u8) ![]const u8 {
        const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_url, path });
        defer self.allocator.free(url);

        var headers = std.http.Headers.init(self.allocator);
        defer headers.deinit();

        try headers.append("Authorization", try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key}));
        try headers.append("Content-Type", "application/json");

        var request = try self.client.open(.POST, try std.Uri.parse(url), headers, .{});
        defer request.deinit();

        try request.send();
        try request.writeAll(request_body);
        try request.finish();

        try request.wait();

        if (request.response.status != .ok) {
            return self.handleError(request.response.status);
        }

        const body = try request.reader().readAllAlloc(self.allocator, 1024 * 1024 * 10); // 10MB limit
        return body;
    }

    /// Make a streaming POST request for Server-Sent Events
    pub fn postStream(self: *HttpClient, path: []const u8, request_body: []const u8) !StreamIterator {
        const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_url, path });
        defer self.allocator.free(url);

        var headers = std.http.Headers.init(self.allocator);
        defer headers.deinit();

        try headers.append("Authorization", try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key}));
        try headers.append("Content-Type", "application/json");
        try headers.append("Accept", "text/event-stream");
        try headers.append("Cache-Control", "no-cache");

        var request = try self.client.open(.POST, try std.Uri.parse(url), headers, .{});
        errdefer request.deinit();

        try request.send();
        try request.writeAll(request_body);
        try request.finish();

        try request.wait();

        if (request.response.status != .ok) {
            return self.handleError(request.response.status);
        }

        const buffer = try self.allocator.alloc(u8, 1024);
        return StreamIterator{
            .allocator = self.allocator,
            .reader = request.reader().any(),
            .buffer = buffer,
            .buffer_capacity = 1024,
            .buffer_len = 0,
            .request = request,
        };
    }

    fn handleError(self: HttpClient, status: std.http.Status) Error {
        _ = self;
        switch (status.class()) {
            .success => unreachable,
            .bad_request => return Error.InvalidRequest,
            .unauthorized => return Error.AuthenticationError,
            .forbidden => return Error.AuthenticationError,
            .too_many_requests => return Error.RateLimitError,
            .server_error => return Error.ServerError,
            else => return Error.NetworkError,
        }
    }
};

/// Iterator for Server-Sent Events streaming
pub const StreamIterator = struct {
    allocator: std.mem.Allocator,
    reader: std.io.AnyReader,
    buffer: []u8,
    buffer_capacity: usize,
    buffer_len: usize,
    request: std.http.Client.Request,
    finished: bool = false,

    pub fn next(self: *StreamIterator) !?[]const u8 {
        if (self.finished) return null;

        self.buffer_len = 0;

        while (true) {
            const byte = self.reader.readByte() catch |err| switch (err) {
                error.EndOfStream => {
                    self.finished = true;
                    self.request.deinit();
                    return null;
                },
                else => return error.NetworkError,
            };

            if (byte == '\n') {
                if (self.buffer_len > 0) {
                    const line = try self.allocator.dupe(u8, self.buffer[0..self.buffer_len]);
                    self.buffer_len = 0;

                    // Skip empty lines and comments
                    if (line.len == 0 or (line.len > 0 and line[0] == ':')) {
                        self.allocator.free(line);
                        continue;
                    }

                    // Parse SSE format: "data: {json}"
                    if (std.mem.startsWith(u8, line, "data: ")) {
                        const data = line[6..];
                        if (std.mem.eql(u8, data, "[DONE]")) {
                            self.allocator.free(line);
                            self.finished = true;
                            self.request.deinit();
                            return null;
                        }
                        return data;
                    }

                    self.allocator.free(line);
                }
            } else {
                if (self.buffer_len < self.buffer_capacity) {
                    self.buffer[self.buffer_len] = byte;
                    self.buffer_len += 1;
                }
            }
        }
    }

    pub fn deinit(self: *StreamIterator) void {
        if (self.buffer_capacity > 0) {
            self.allocator.free(self.buffer);
        }
        if (!self.finished) {
            self.request.deinit();
        }
    }
};

/// JSON parsing utilities for OpenAI responses
pub const JsonParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) JsonParser {
        return JsonParser{ .allocator = allocator };
    }

    pub fn parseChatCompletion(self: JsonParser, json_str: []const u8) !models.ChatCompletionResponse {
        const parsed = try std.json.parseFromSlice(
            models.ChatCompletionResponse,
            self.allocator,
            json_str,
            .{ .ignore_unknown_fields = true },
        );
        return parsed.value;
    }

    pub fn parseChatCompletionChunk(self: JsonParser, json_str: []const u8) !models.ChatCompletionChunk {
        const parsed = try std.json.parseFromSlice(
            models.ChatCompletionChunk,
            self.allocator,
            json_str,
            .{ .ignore_unknown_fields = true },
        );
        return parsed.value;
    }
};

test "http client initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const client = HttpClient.init(allocator, "test-key", null);
    defer client.deinit();

    try testing.expect(std.mem.eql(u8, client.api_key, "test-key"));
    try testing.expect(std.mem.eql(u8, client.base_url, "https://api.openai.com/v1"));
}

test "stream iterator basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Mock SSE data
    const sse_data =
        "data: {\"id\":\"test\",\"object\":\"chat.completion.chunk\"}\n" ++
        "data: {\"id\":\"test2\",\"object\":\"chat.completion.chunk\"}\n" ++
        "data: [DONE]\n";

    var fbs = std.io.fixedBufferStream(sse_data);
    const buffer = try allocator.alloc(u8, 256);
    var iter = StreamIterator{
        .allocator = allocator,
        .reader = fbs.reader().any(),
        .buffer = buffer,
        .buffer_capacity = 256,
        .buffer_len = 0,
        .request = undefined, // Not used in this test
    };
    defer iter.deinit();

    const chunk1 = try iter.next();
    try testing.expect(chunk1 != null);
    try testing.expect(std.mem.startsWith(u8, chunk1.?, "{\"id\":\"test\"}"));
    allocator.free(chunk1.?);

    const chunk2 = try iter.next();
    try testing.expect(chunk2 != null);
    try testing.expect(std.mem.startsWith(u8, chunk2.?, "{\"id\":\"test2\"}"));
    allocator.free(chunk2.?);

    const chunk3 = try iter.next();
    try testing.expect(chunk3 == null);
}
