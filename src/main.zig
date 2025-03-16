const std = @import("std");
const math = std.math;
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const overlaps = c.SDL_HasIntersection;

const FPS = 120;
const DELTA_TIME_SEC: f32 = 1.0 / @as(f32, FPS);

const Window = struct {
    const Width: f32 = 800;
    const Height: f32 = 600;
    const BgColor = 0xFF181818;
};

// --- Game objects ---
const Projectile = struct {
    const Size: f32 = 25 * 0.8;
    const Speed: f32 = 350;
    const Color: usize = 0xFFFFFFFF;
    x: f32,
    y: f32,
    dx: f32,
    dy: f32,

    fn init() Projectile {
        return .{
            .x = (Window.Width / 2) - (Projectile.Size / 2),
            .y = Bar.Y - (Bar.Thiccness / 2) - Projectile.Size,
            .dx = 1,
            .dy = 1,
        };
    }
};

const Bar = struct {
    const Length: f32 = 100;
    const Thiccness: f32 = Projectile.Size;
    const Y: f32 = Window.Height - Projectile.Size - 50;
    const Speed: f32 = Projectile.Speed * 1.5;
    const Color: usize = 0xFF3030FF;
    x: f32,
    dx: f32,

    fn init() Bar {
        return .{
            .x = (Window.Width / 2) - (Bar.Length / 2),
            .dx = 0,
        };
    }
};

const Target = struct {
    const Width: f32 = Bar.Length;
    const Height: f32 = Projectile.Size;
    const PaddingX = 20;
    const PaddingY = 50;
    const Rows = 4;
    const Cols = 5;
    const GridWidth = (Target.Cols * Target.Width) + (Target.Cols - 1) * Target.PaddingX;
    const GridX = (Window.Width / 2) - Target.GridWidth / 2;
    const GridY = 50;
    const Color = 0xFF30FF30;
    x: f32,
    y: f32,
    dead: bool = false,
};

const GameStatus = enum {
    NotStarted,
    Live,
    Paused,
    End,
};

fn init_targets() [Target.Rows * Target.Cols]Target {
    comptime var targets: [Target.Rows * Target.Cols]Target = undefined;
    inline for (0..Target.Rows) |row| {
        inline for (0..Target.Cols) |col| {
            targets[row * Target.Cols + col] = Target{
                .x = Target.GridX + (@as(f32, col) * (Target.Width + Target.PaddingX)),
                .y = Target.GridY + @as(f32, row) * Target.PaddingY,
            };
        }
    }
    return targets;
}

// --- All mutable state is in a single nested global ---
const State = struct {
    status: GameStatus = .NotStarted,
    score: u32 = 0,
    projectile: Projectile = Projectile.init(),
    bar: Bar = Bar.init(),
    targets: [Target.Cols * Target.Rows]Target = init_targets(),

    const Self = @This();

    fn revive_targets(self: *Self) void {
        for (&self.targets) |*target| {
            target.dead = false;
        }
        self.score = 0;
    }

    fn handle_input(self: *Self, keyboard: [*]const u8) void {
        self.bar.dx = 0;
        // Handle left movement
        if (keyboard[c.SDL_SCANCODE_A] == 1) {
            self.bar.dx = -1;
            if (self.status != .Live) {
                self.status = .Live;
                self.projectile.dx = -1;
            }
        }
        // Handle right movement
        if (keyboard[c.SDL_SCANCODE_D] == 1) {
            self.bar.dx = 1;
            if (self.status != .Live) {
                self.status = .Live;
                self.projectile.dx = 1;
            }
        }
    }

    /// --- State handling ---
    fn update(self: *Self, delta_time: f32) void {
        if (self.status != .Live) {
            return;
        }

        if (self.score == Target.Rows * Target.Cols) {
            self.revive_targets();
        }

        // If collision between projectile and bar found, update projectile y-coordinate
        const proj_rect = get_projectile_rect(self.projectile.x, self.projectile.y);
        const bar_rect = get_bar_rect(self.bar.x);
        if (overlaps(&proj_rect, &bar_rect) != 0) {
            self.projectile.y = Bar.Y - (Bar.Thiccness / 2) - (Projectile.Size) - 1.0;
            return;
        }

        self.update_bar_x(delta_time);
        self.update_proj_x(delta_time);
        self.update_proj_y(delta_time);
    }

    fn update_proj_x(self: *Self, delta_time: f32) void {
        const proj_next_x: f32 = self.projectile.x + self.projectile.dx * Projectile.Speed * delta_time;

        // Check if projectile has reached horizontal edges of window, reverse if collided
        if (proj_next_x < 0 or proj_next_x + Projectile.Size > Window.Width) {
            self.projectile.dx *= -1;
            return;
        }

        // Check if projectile has collided with bar, reverse if collided
        const projectile_rect = get_projectile_rect(proj_next_x, self.projectile.y);
        const bar_rect = get_bar_rect(self.bar.x);
        if (overlaps(&bar_rect, &projectile_rect) != 0) {
            self.projectile.dx *= -1;
            return;
        }

        // Check if projectile has collided with a target,
        // reverse direction AND destroy target if collided
        for (&self.targets) |*target| {
            // Skip dead targets
            if (target.dead) {
                continue;
            }
            if (overlaps(&get_target_rect(target.*), &projectile_rect) != 0) {
                target.dead = true;
                self.score += 1;
                self.projectile.dx *= -1;
                return;
            }
        }

        // If no collisions, update projectile with new x-coordinate
        self.projectile.x = proj_next_x;
    }

    fn update_proj_y(self: *Self, delta_time: f32) void {
        const proj_next_y: f32 = self.projectile.y + self.projectile.dy * Projectile.Speed * delta_time;

        // Check if projectile has reached vertical edges of window, reverse if collided
        if (proj_next_y < 0 or proj_next_y + Projectile.Size > Window.Height) {
            self.projectile.dy *= -1;
            return;
        }

        // Check if projectile has collided with bar, reverse if collided
        const projectile_rect = get_projectile_rect(self.projectile.x, proj_next_y);
        if (overlaps(&get_bar_rect(self.bar.x), &projectile_rect) != 0) {
            self.projectile.dy *= -1;
            return;
        }

        // Check if projectile has collided with a target,
        // reverse direction AND destroy target if collided
        for (&self.targets) |*target| {
            // Skip dead targets
            if (target.dead) {
                continue;
            }
            if (overlaps(&get_target_rect(target.*), &projectile_rect) != 0) {
                target.dead = true;
                self.score += 1;
                self.projectile.dy *= -1;
                return;
            }
        }

        // No collisions, update projectile with new y-coordinate
        self.projectile.y = proj_next_y;
    }

    fn update_bar_x(self: *Self, delta_time: f32) void {
        // Clamp bar x-coordinates to within the window
        const bar_next_x: f32 = math.clamp(self.bar.x + self.bar.dx * Bar.Speed * delta_time, 0, Window.Width - Bar.Length);

        // Check if bar collides with projectile
        const proj_rect = get_projectile_rect(self.projectile.x, self.projectile.y);
        const bar_rect = get_bar_rect(bar_next_x);
        if (overlaps(&proj_rect, &bar_rect) != 0) {
            return;
        }

        // No collisions, update bar with new x-coordinate
        self.bar.x = bar_next_x;
    }

    /// --- Rendering ---
    fn render(self: *Self, renderer: *c.SDL_Renderer) void {
        // Render bg
        set_color(renderer, Window.BgColor);
        _ = c.SDL_RenderClear(renderer);

        // Render bar
        set_color(renderer, Bar.Color);
        const bar_rect = get_bar_rect(self.bar.x);
        _ = c.SDL_RenderFillRect(renderer, &bar_rect);

        // Render projectile
        set_color(renderer, Projectile.Color);
        const proj_rect = get_projectile_rect(self.projectile.x, self.projectile.y);
        _ = c.SDL_RenderFillRect(renderer, &proj_rect);

        // Render targets
        set_color(renderer, Target.Color);
        for (self.targets) |target| {
            if (!target.dead) {
                const target_rect = get_target_rect(target);
                _ = c.SDL_RenderFillRect(renderer, &target_rect);
            }
        }

        // Render window
        _ = c.SDL_RenderPresent(renderer);
    }
};
var state: State = .{};

///--- Rendering ---
fn get_rect(x: f32, y: f32, width: f32, height: f32) c.SDL_Rect {
    return c.SDL_Rect{
        .x = @intFromFloat(x),
        .y = @intFromFloat(y),
        .w = @intFromFloat(width),
        .h = @intFromFloat(height),
    };
}

fn get_projectile_rect(x: f32, y: f32) c.SDL_Rect {
    return get_rect(x, y, Projectile.Size, Projectile.Size);
}

fn get_bar_rect(x: f32) c.SDL_Rect {
    // Bar's Y-axis tracks the center of the bar
    return get_rect(x, Bar.Y - (Bar.Thiccness / 2), Bar.Length, Bar.Thiccness);
}

fn get_target_rect(target: Target) c.SDL_Rect {
    return get_rect(target.x, target.y, Target.Width, Target.Height);
}

fn set_color(renderer: *c.SDL_Renderer, color: u32) void {
    // NOTE; `@truncate` removes from MOST SIGNIFICANT BITS
    const r: u8 = @truncate(color >> (0 * 8) & 0xFF);
    const g: u8 = @truncate(color >> (1 * 8) & 0xFF);
    const b: u8 = @truncate(color >> (2 * 8) & 0xFF);
    const a: u8 = @truncate(color >> (3 * 8) & 0xFF);
    _ = c.SDL_SetRenderDrawColor(renderer, r, g, b, a);
}

/// --- SDL handler ---
pub const SDL = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    keyboard: [*]const u8,

    const Self = @This();
    pub fn init() !Self {
        const window = c.SDL_CreateWindow("breakout!", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, Window.Width, Window.Height, c.SDL_WINDOW_OPENGL) orelse
            {
                c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
                return error.SDLInitializationFailed;
            };
        const renderer = c.SDL_CreateRenderer(window, -1, 0) orelse {
            c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        const keyboard = c.SDL_GetKeyboardState(null) orelse {
            c.SDL_Log("Unable to obtain keyboard: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        return Self{
            .window = window,
            .renderer = renderer,
            .keyboard = keyboard,
        };
    }

    // Deinit in reverse order of init
    pub fn deinit(self: *const Self) void {
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }
};

pub fn main() !void {
    const sdl = try SDL.init();
    defer sdl.deinit();

    while (state.status != .End) {
        // Handle user input
        // NOTE: this is triggered once per frame
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    state.status = .End;
                },
                c.SDL_KEYDOWN => {
                    switch (event.key.keysym.scancode) {
                        c.SDL_SCANCODE_SPACE => {
                            state.status = if (state.status == .Live) GameStatus.Paused else GameStatus.Live;
                        },
                        c.SDL_SCANCODE_Q => {
                            state.status = .End;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        // Handle movement
        // NOTE: we track movement via `GetKeyboardState` cuz updating direction
        // via `PollEvent` only occurs once per frame (60x per second when running in 60fps)
        // which results in a less smooth experience.
        state.handle_input(sdl.keyboard);

        // Update bar, target, projectile states
        state.update(DELTA_TIME_SEC);

        // Render
        state.render(sdl.renderer);

        // Delay to enforce fixed fps
        c.SDL_Delay(1000 / FPS);
    }
}
