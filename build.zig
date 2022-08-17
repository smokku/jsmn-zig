const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("jsmn", "src/jsmn.zig");
    lib.setBuildMode(mode);
    lib.install();

    const main_tests = b.addTest("src/jsmn.zig");
    main_tests.setBuildMode(mode);
    const test_tests = b.addTest("src/tests.zig");
    test_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
    test_step.dependOn(&test_tests.step);
}
