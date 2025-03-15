const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "breakout",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const sdl_dep = b.dependency("SDL", .{
        .optimize = .ReleaseFast,
        .target = target,
    });
    exe.linkLibrary(sdl_dep.artifact("SDL2"));

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    const install = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install.step);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run = b.addRunArtifact(exe);
    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run.step.dependOn(&install.step);
    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run.addArgs(args);
    }
    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    b.step("run", "Run the app").dependOn(&run.step);

    const zip_dep = b.dependency("zip", .{});
    const host_zip_exe = b.addExecutable(.{
        .name = "zip",
        .root_source_file = zip_dep.path("src/zip.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });

    const ci_step = b.step("ci", "The build/test step to run on the CI");
    ci_step.dependOn(&install.step);
    try ci(b, ci_step, host_zip_exe);
}

fn ci(
    b: *std.Build,
    ci_step: *std.Build.Step,
    host_zip_exe: *std.Build.Step.Compile,
) !void {
    const ci_targets = [_][]const u8{
        "x86_64-linux",
        "x86_64-macos",
        // "x86_64-windows",
        "aarch64-linux",
        "aarch64-macos",
        // "aarch64-windows",
        // "arm-linux",
        // "riscv64-linux",
        // "powerpc-linux",
        // "powerpc64le-linux",
    };

    const make_archive_step = b.step("archive", "Create CI archives");
    ci_step.dependOn(make_archive_step);

    for (ci_targets) |ci_target_str| {
        const target = b.resolveTargetQuery(try std.Target.Query.parse(
            .{ .arch_os_abi = ci_target_str },
        ));

        const optimize: std.builtin.OptimizeMode = .ReleaseSafe;
        const breakout_exe = b.addExecutable(.{
            .name = "breakout",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        const sdl_dep = b.dependency("SDL", .{
            .optimize = .ReleaseFast,
            .target = target,
        });
        breakout_exe.linkLibrary(sdl_dep.artifact("SDL2"));

        const breakout_exe_install = b.addInstallArtifact(breakout_exe, .{
            .dest_dir = .{ .override = .{ .custom = ci_target_str } },
        });
        ci_step.dependOn(&breakout_exe_install.step);

        make_archive_step.dependOn(makeCiArchiveStep(
            b,
            ci_target_str,
            target.result,
            breakout_exe_install,
            host_zip_exe,
        ));
    }
}

fn makeCiArchiveStep(
    b: *std.Build,
    ci_target_str: []const u8,
    target: std.Target,
    breakout_exe_install: *std.Build.Step.InstallArtifact,
    host_zip_exe: *std.Build.Step.Compile,
) *std.Build.Step {
    const install_path = b.getInstallPath(.prefix, ".");

    if (target.os.tag == .windows) {
        const out_zip_file = b.pathJoin(&.{
            install_path,
            b.fmt("breakout-{s}.zip", .{ci_target_str}),
        });
        const zip = b.addRunArtifact(host_zip_exe);
        zip.addArg(out_zip_file);
        zip.addArg("breakout.exe");
        zip.addArg("breakout.pdb");
        zip.cwd = .{ .cwd_relative = b.getInstallPath(
            breakout_exe_install.dest_dir.?,
            ".",
        ) };
        zip.step.dependOn(&breakout_exe_install.step);
    }

    const targz = b.pathJoin(&.{
        install_path,
        b.fmt("breakout-{s}.tar.gz", .{ci_target_str}),
    });
    const tar = b.addSystemCommand(&.{
        "tar",
        "-czf",
        targz,
        "breakout",
    });
    tar.cwd = .{ .cwd_relative = b.getInstallPath(
        breakout_exe_install.dest_dir.?,
        ".",
    ) };
    tar.step.dependOn(&breakout_exe_install.step);
    return &tar.step;
}
