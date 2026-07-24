# Fork changes

Personal fork of [niri](https://github.com/niri-wm/niri) carrying features that are **not
upstream** (and, where noted, were explicitly declined upstream). Branch `background-render`,
based on a niri **release tag** (rebased forward on each release — never on `main`).

Not intended for upstream merge. See per-feature notes for rationale.

| Feature | Config | Default when absent | Commits |
|---|---|---|---|
| Per-workspace background render | `background-render-fps <N \| "auto">` on a named `workspace {}` | off (stock 1 Hz idle floor) | `28f597f9`, `a6464c73` |

---

## Per-workspace background render

Keeps windows on a **named, hidden** workspace receiving frame callbacks at a chosen rate,
instead of dropping to niri's 1 Hz idle floor when that workspace's output stops rendering.
Fixes background games (on an inactive workspace) stalling audio and freezing frames.

```kdl
workspace "gaming" {
    open-on-output "DP-4"
    background-render-fps "auto"   // or a fixed number, e.g. 144
}
```

- `<N>` — fixed fps while hidden.
- `"auto"` — resolves per-tick to that workspace's **output refresh rate** (fallback 60 if
  unknown). Quoted; bare `auto` is invalid KDL.
- Absent or `0` — feature off; that workspace behaves exactly like stock niri.

**How:** a second event-loop fallback timer (`send_frame_callbacks_for_background_workspaces`
in `src/niri.rs`) drives `Layout::with_background_render_windows_mut` (`src/layout/mod.rs`),
riding the existing `MappedWindow::needs_frame_callback` path. No hot-path or scanout-gate
changes. Self-paces: re-arms at the fastest configured fps among hidden flagged workspaces,
1 s when none are active.

**Why not upstream:** maintainer declined the concept
([niri Discussion #1525](https://github.com/niri-wm/niri/discussions/1525)) — power-by-default,
"fix the app not the compositor". Design notes:
`docs/superpowers/specs/2026-07-24-niri-background-render-design.md`.

**Verified:** nested niri (hidden flagged workspace held ~output-refresh fps vs ~1 fps control)
and live on DRM/NVIDIA with a real game.

---

## Maintenance

- **Base:** a release tag, not `main`. GitHub showing "N commits behind" vs upstream `main`
  is expected and irrelevant — do **not** "Sync fork".
- **Rebase on a new niri release:**
  ```sh
  git fetch origin --tags
  git rebase <new-tag> background-render
  cargo build --release
  sudo install -Dm755 target/release/niri /usr/local/bin/niri   # takes PATH precedence
  git push -f fork background-render                              # keep the offsite backup current
  # log out / back in to activate the new binary
  ```
- **Install model:** `/usr/local/bin/niri` shadows the packaged `/usr/bin/niri`; revert = `rm`.
