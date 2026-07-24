# Per-workspace background render — design

Personal patch-branch feature. **Not upstreamable** — maintainer rejected the concept
(niri-wm/niri Discussion #1525: *"that's the entire point, not asking programs to draw a
frame when they're invisible"*). Carried on branch `background-render`, rebased on each
niri release tag. Keep the diff tiny (3 files + 1 layout helper) to minimize rebase cost.

## Problem

A game on an inactive workspace stalls: audio underruns, frames freeze, then jump on
return. Root cause is Wayland frame-callback throttling, and specifically niri's *idle
floor*:

- niri already sends frame callbacks to hidden-workspace windows via
  `MappedWindow::needs_frame_callback` (`src/window/mapped.rs`), set on commit
  (`mapped.rs:1113`). The render path reaches them because `windows_for_output_mut`
  (`src/layout/mod.rs:1646`) iterates **all** workspaces on the monitor.
- So while the output keeps rendering (its visible workspace is busy), the hidden game
  keeps ~full fps.
- When the output goes **idle** (nothing visible changing), the only remaining pump is
  the 1 Hz fallback timer (`src/niri.rs:2438`, `send_frame_callbacks_on_fallback_timer`,
  throttle `FRAME_CALLBACK_THROTTLE = 995ms`). The game drops to ~1 fps → stall.

Hyprland's `render_unfocused` has the same class of bug (hyprwm/Hyprland #12463, #12339)
because it ties callbacks to the monitor render cycle. We avoid it with an **independent
timer**.

## Design

Raise the idle floor from 1 Hz to a per-workspace configured fps, for opt-in named
workspaces. A second fallback timer, faster, scoped. **No change to `should_send` /
scanout-output gating.**

### 1. Config (`niri-config/src/workspace.rs`)

Add a child to the existing `Workspace` struct:

```kdl
workspace "game" {
    background-render-fps 60
}
```

```rust
#[knuffel(child, unwrap(argument))]
pub background_render_fps: Option<u16>,
```

Absent or `0` → off (default niri behaviour). Named workspaces only.

### 2. Runtime state (`src/layout/workspace.rs`)

Carry `background_render_fps: Option<u16>` on the layout `Workspace`, populated where
named-workspace config is applied to the layout.

### 3. Timer (`src/niri.rs`, mirror lines 2436–2444)

- Interval = `1000 / max(configured fps across flagged workspaces)` ms.
- Tick → `Niri::send_frame_callbacks_for_background_workspaces()`.
- Armed only when ≥1 workspace has `fps > 0`; re-evaluated on config reload. No flagged
  workspaces → not armed → zero cost.

### 4. Tick (`src/niri.rs` + layout helper)

```
layout.with_background_render_windows_mut(|mapped, output, fps| {
    let throttle = Some(Duration::from_secs_f64(0.95 / fps as f64));
    mapped.send_frame(output, now, throttle, |_, _| None);
});
```

`with_background_render_windows_mut` (new, `src/layout/mod.rs`) walks monitors, **skips
each monitor's active workspace** (visible → normal render path drives it), filters
`background_render_fps > 0`, and yields `(&mut MappedWindow, &Output, u16)`. The
`|_,_| None` closure + `needs_frame_callback` is exactly the fallback-timer mechanism.

### 5. Throttle math

`send_frame`'s `throttle` dedups per surface via `SurfaceFrameThrottlingState.last_sent_at`.
`0.95/fps` mirrors niri's 995/1000 fudge so timer jitter never drops us below target.
Render path + timer cannot double-send (shared throttle state).

## Edge cases

- Workspace becomes active → skipped in tick; render path drives it. Throttle prevents overlap.
- `fps = 0` / unset → off.
- No flagged workspaces → timer not armed.
- Config reload → recompute armed-state + interval.
- Multi-output → each flagged workspace uses its own monitor's output.
- Power → cost only while a flagged workspace is hidden.

## Diff footprint

1. `niri-config/src/workspace.rs` — 1 field.
2. `src/layout/workspace.rs` (+ config-apply site) — 1 field + populate.
3. `src/layout/mod.rs` — 1 iterator helper.
4. `src/niri.rs` — 1 timer + 1 tick fn (~30 lines).

No hot-path edits.

## Verification

- `niri validate` on a config with `background-render-fps`.
- Live: vsynced game on a named workspace; switch away so its output goes fully idle
  (nothing else moving); confirm audio continues and no freeze/jump on return. Compare
  unpatched 1 Hz vs configured fps.
