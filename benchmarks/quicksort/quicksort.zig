// Quicksort, from the Rosetta Code Zig entry (in-place array, comptime compare).
// main generates the same MINSTD sequence as quicksort.trk, sorts, and prints the
// same order-dependent checksum, so the two languages cross-check each other.
const std = @import("std");

pub fn quickSort(comptime T: type, arr: []T, comptime compareFn: fn (T, T) bool) void {
    if (arr.len < 2) return;
    const pivot_index = partition(T, arr, compareFn);
    quickSort(T, arr[0..pivot_index], compareFn);
    quickSort(T, arr[pivot_index + 1 .. arr.len], compareFn);
}

fn partition(comptime T: type, arr: []T, comptime compareFn: fn (T, T) bool) usize {
    const pivot_index = arr.len / 2;
    const last_index = arr.len - 1;
    std.mem.swap(T, &arr[pivot_index], &arr[last_index]);
    var store_index: usize = 0;
    for (arr[0 .. arr.len - 1]) |*elem_ptr| {
        if (compareFn(elem_ptr.*, arr[last_index])) {
            std.mem.swap(T, elem_ptr, &arr[store_index]);
            store_index += 1;
        }
    }
    std.mem.swap(T, &arr[store_index], &arr[last_index]);
    return store_index;
}

fn lessThan(a: i64, b: i64) bool {
    return a < b;
}

// Zig 0.16 "Juicy Main": args + arena + io arrive via std.process.Init.
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len < 2) return error.MissingN;
    const n = try std.fmt.parseInt(usize, args[1], 10);

    const arr = try a.alloc(i64, n);
    var x: u64 = 42;
    for (arr) |*e| {
        x = (48271 * x) % 2147483647;
        e.* = @intCast(x);
    }

    quickSort(i64, arr, lessThan);

    var acc: u64 = 0;
    for (arr, 0..) |v, i| {
        acc = (acc + (@as(u64, @intCast(i + 1)) * @as(u64, @intCast(v)))) % 1000000007;
    }

    var buf: [64]u8 = undefined;
    var w = std.Io.File.stdout().writer(init.io, &buf);
    const stdout = &w.interface;
    try stdout.print("{d}\n", .{acc});
    try stdout.flush();
}
