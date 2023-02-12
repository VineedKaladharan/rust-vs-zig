const std = @import("std");
const Conf = @import("conf.zig");
const Chunk = @import("chunk.zig").Chunk;
const GC = @import("gc.zig");
const Value = @import("value.zig").Value;
const mem = std.mem;
const Allocator = mem.Allocator;

const Obj = @This();

pub const Type = enum {
    String,
    Function,
    NativeFunction,
    Closure,
    Upvalue,

    pub fn obj_struct(comptime self: Type) type {
        return switch (self) {
            Type.String => String,
            Type.Function => Function,
            Type.NativeFunction => NativeFunction,
            Type.Closure => Closure,
            Type.Upvalue => Upvalue,
        };
    }

    pub fn from_obj(comptime ObjType: type) Type {
        return Type.from_obj_safe(ObjType) orelse @panic("invalid obj type");
    }

    pub fn from_obj_safe(comptime ObjType: type) ?Type {
        return switch (ObjType) {
            String => Type.String,
            Function => Type.Function,
            NativeFunction => Type.NativeFunction,
            Closure => Type.Closure,
            Upvalue => Type.Upvalue,
            else => null,
        };
    }
};

type: Type,
is_marked: bool,
next: ?*Obj = null,

pub fn narrow(self: *Obj, comptime ParentType: type) *ParentType {
    if (comptime Conf.SAFE_OBJ_CAST) {
        return self.safe_narrow(ParentType) orelse @panic("invalid cast");
    }
    return @fieldParentPtr(ParentType, "obj", self);
}

pub fn safe_narrow(self: *Obj, comptime ParentType: type) ?*ParentType {
    if (self.type != Type.from_obj(ParentType)) return null;
    return narrow(self, ParentType);
}

pub fn is(self: *Obj, comptime ParentType: type) bool {
    return self.type == Type.from_obj(ParentType);
}

pub fn print(self: *Obj, writer: anytype) void {
    switch (self.type) {
        inline else => |ty| {
            self.narrow(Type.obj_struct(ty)).print(writer);
        },
    }
}

pub const String = struct {
    obj: Obj,
    len: u32,
    hash: u32,
    chars: [*]const u8,

    pub fn as_string(self: *String) []const u8 {
        return self.chars[0..self.len];
    }

    pub fn eq(a: *String, b: *String) bool {
        if (a.len != b.len) return false;
        return mem.eql(u8, a.chars[0..a.len], b.chars[0..b.len]);
    }

    pub inline fn widen(self: *String) *Obj {
        return @ptrCast(*Obj, self);
    }

    pub fn print(self: *String, writer: anytype) void {
        writer.print("\"{s}\"", .{self.chars[0..self.len]});
    }
};

pub const Function = struct {
    obj: Obj,
    arity: u8,
    upvalue_count: u32,
    name: ?*String,
    chunk: Chunk,

    pub fn init(self: *Function, allocator: Allocator) !void {
        self.arity = 0;
        self.name = null;
        self.upvalue_count = 0;
        self.chunk = try Chunk.init(allocator);
    }

    pub inline fn widen(self: *Function) *Obj {
        return @ptrCast(*Obj, self);
    }

    pub fn print(self: *Function, writer: anytype) void {
        _ = self;
        // TODO: unfuck this
        // const name = if (self.name) |name| name.chars[0..name.len] else return writer.print("<script>", .{});
        // writer.print("<fn {s}>", .{name});
        writer.print("<fn >", .{});
    }

    pub fn name_str(self: *Function) []const u8 {
        return if (self.name) |name| name.chars[0..name.len] else "script";
    }
};

pub const NativeFunction = struct {
    obj: Obj,
    function: NativeFn,

    /// A function pointer
    pub const NativeFn = *const fn(u8, []Value) Value;

    pub fn init(self: *NativeFunction, function: NativeFn) void {
        self.function = function;
    }

    pub fn print(self: *NativeFunction, writer: anytype) void {
        _ = self;
        writer.print("<native fn>", .{});
    }

    pub fn widen(self: *NativeFunction) *Obj {
        return @ptrCast(*Obj, self);
    }
};

pub const Closure = struct {
    obj: Obj,
    function: *Function,
    upvalues: [*]*Upvalue,
    upvalues_len: u32,

    pub fn init(gc: *GC, function: *Function) !*Closure {
        const upvalues = try gc.as_allocator().alloc(?*Upvalue, function.upvalue_count);
        for (upvalues) |*upvalue| {
            upvalue.* = std.mem.zeroes(?*Upvalue);
        }
        const self: Closure = .{
            .obj = Obj{
                .type = Type.Closure,
                .is_marked = false,
                .next = null,
            },
            .function = function,
            .upvalues = @ptrCast([*]*Upvalue, upvalues),
            .upvalues_len = function.upvalue_count,
        };

        var ptr = try gc.alloc_obj(Obj.Closure);
        ptr.* = self;

        return ptr;
    }

    pub fn print(self: *Closure, writer: anytype) void {
        const name = self.function.name_str();
        writer.print("<closure> {s}\n", .{ name});
    }

    pub fn widen(self: *Closure) *Obj {
        return @ptrCast(*Obj, self);
    }
};

pub const Upvalue = struct {
    obj: Obj,
    location: *Value,
    closed: Value,
    next: ?*Upvalue = null,

    pub fn init(self: *Upvalue, value: *Value) void {
        self.location = value;
        self.closed = Value.nil();
        self.next = null;
    }

    pub fn print(self: *Upvalue, writer: anytype) void {
        _ = self;
        writer.print("upvalue", .{});
    }

    pub fn widen(self: *Upvalue) *Obj {
        return @ptrCast(*Obj, self);
    }
};