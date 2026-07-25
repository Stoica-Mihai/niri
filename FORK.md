# Fork changes

Personal fork of [niri](https://github.com/niri-wm/niri) carrying features that are **not
upstream** (and, where noted, were explicitly declined upstream). Trunk branch `main`, based
on a niri **release tag** (rebased forward on each release — never on upstream's `main`; niri's
tags are cut from main, so a release tag is just main at a stable checkpoint).

Not intended for upstream merge. See per-feature notes for rationale.

| Feature | Config | Default when absent | Commits |
|---|---|---|---|
| Per-workspace background render | `background-render-fps <N \| "auto">` on a named `workspace {}` | off (stock 1 Hz idle floor) | `28f597f9`, `a6464c73` |
| Restore view on un-maximize | `restore-view-on-unmaximize` in `layout {}` | off (stock re-aligns the view) | see below |
| Hold-to-peek | `peek-column-left` / `-right` / `-first` / `-last` / `peek-end` actions | n/a (bind them to use) | see below |

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

## Restore view on un-maximize

Toggling `maximize-column` (`Mod+F`) off returns the view to the scroll position it had before
maximizing, instead of re-aligning the view to the column. Two windows that were side by side are
side by side again; stock niri instead scrolls the column to the screen edge, pushing its neighbour
off-view until you scroll back manually.

```kdl
layout {
    restore-view-on-unmaximize
}
```

Absent (default) — stock behavior. Applies to un-fullscreen as well as un-maximize.

**How:** `maximize-column` is `toggle_full_width()`, a column *width* change that never alters the
column's `SizingMode`. niri's existing view save/restore (`view_offset_to_restore`) keys off the
normal↔fullscreen/maximized `SizingMode` transition, so it never observes this toggle at all —
verified at runtime: across 137 `update_window` calls during a maximize/un-maximize cycle the mode
stayed `Normal` and the store/restore never fired.

So this adds a second, separate snapshot: `ScrollingSpace::view_offset_before_maximize` is captured
in `toggle_full_width()` before the column widens, and consumed in `update_window()` on the width
change that follows the collapse (`restore_view_after_unmaximize`). Both are dropped by
`clear_view_offsets_to_restore()` wherever the active column changes or is removed, so a stale
offset cannot leak. A separate field is required: reusing `view_offset_to_restore` would trip
niri's own debug invariant, which asserts that a set value implies a fullscreen/maximized column.

**Tests:** `unmaximize_restores_view_with_option` and `unmaximize_recenters_view_without_option` in
`src/layout/tests.rs` — the second asserts the views *differ* without the option, so it guards that
the first is actually discriminating.

**Verified:** live in nested niri with a native Wayland client (kitty), two columns side by side,
`Mod+F` twice — option on restores side-by-side, option off reproduces stock behavior.

---

## Hold-to-peek

Look at another column without leaving the one you're working in. The view scrolls with niri's
normal animation, focus never moves, and releasing the modifier animates back to the exact offset
you started from.

```kdl
binds {
    Mod+Alt+H repeat=false { peek-column-left; }
    Mod+Alt+L repeat=false { peek-column-right; }
    Mod+Alt+U repeat=false { peek-column-first; }
    Mod+Alt+I repeat=false { peek-column-last; }
}
```

Steps accumulate: hold the modifier and keep tapping to wander in either direction, then release to
return — there is only ever one restore point. Columns already fully on screen are skipped, so a
press always reveals something. `peek-end` returns early; changing the active column, closing a
window or switching workspace ends the peek in place rather than scrolling back.
`peek-column-first` / `peek-column-last` jump the peek to the leftmost / rightmost column
(vim `gg` / `G`); they join the same session, so releasing the modifier still returns to the
one offset you started from.

**How:** `ScrollingSpace::peek_column` (and the absolute `peek_column_first`/`peek_column_last`)
funnel through a shared `commit_peek` that stores the current view offset once, then animates to
the minimum offset that brings the target column into view, rebased onto the active column — which
deliberately does not change, so `view_offset`'s invariant holds. The session ends from
`input/mod.rs`, which fires `PeekEnd` when all modifiers are released while a peek is in progress;
that's the same trigger the MRU window switcher uses, so the bind must be modifier-based.

Two integration points that are easy to miss, both of which cost a live bug before being fixed:

- `update_window()` scrolls the active column back into view on **every client commit** — a blinking
  terminal cursor is enough. A peek has to freeze that path exactly like a view gesture does, or the
  view snaps back within a frame.
- The stored offset is relative to the active column, so it's dropped by
  `clear_view_offsets_to_restore()` whenever that column changes or goes away.

**Tests:** `peek_returns_the_view_and_leaves_focus_alone`, `peek_steps_accumulate_and_still_return`,
`peek_past_the_last_column_keeps_the_session`, `client_commits_do_not_cancel_a_peek`,
`changing_the_active_column_cancels_a_peek`.

**Verified:** live in nested niri with four kitty windows — the view scrolled two columns with focus
still reported on the first window, and `peek-end` restored the original view exactly. The
hold-and-release interaction itself was then confirmed on a real session with `Mod+Alt+H/L`, which
is the only way to exercise the modifier-release trigger (IPC has no modifiers to release).

---

## Maintenance

- **Remotes:** `origin` = upstream `niri-wm/niri` (fetch tags), `fork` = your GitHub fork
  (push; `main` tracks `fork/main`).
- **Base:** a release tag, not upstream `main`. GitHub showing "N commits behind" vs upstream
  `main` is expected and irrelevant — do **not** "Sync fork".
- **Rebase on a new niri release:**
  ```sh
  git fetch origin --tags
  git rebase <new-tag> main
  ./build-fork.sh <rev>            # build + install with version <base>+mcs.<rev>
  git push -f fork main            # keep the offsite backup current
  # log out / back in to activate the new binary
  ```
- **Install model:** `/usr/local/bin/niri` shadows the packaged `/usr/bin/niri`; revert = `rm`.

## Releases (CI)

- **Local (most reliable):** `./build-fork.sh [rev]` — builds + installs, version string
  `<niri-base>+mcs.<rev>`. Matches your exact system.
- **CI build/test gate:** `.github/workflows/ci.yml` (inherited) builds + tests every push.
  On a fork this must be enabled once in the repo's **Actions** tab.
- **Disabled upstream publishing:** `ci.yml`'s `publish-docs` and `publish-wiki` jobs are gated on
  `github.repository == 'niri-wm/niri'`. They fire on pushes to `main`, and on a fork they would
  republish niri's docs site to `gh-pages` under this account and fail on the uninitialized wiki.
- **CI binary release:** `.github/workflows/fork-release.yml` — push a tag `mcs-v<rev>`
  (or run it manually) to build in an Arch container and attach the binary to a GitHub
  Release. Arch/CachyOS-targeted; if library drift breaks it, fall back to `build-fork.sh`.
  Its `verify-ci` job waits for `ci.yml` on the same commit and aborts unless `test`, `clippy`,
  `rustfmt`, `msrv` and `check feature combinations` all succeeded, so a tag can't publish a binary
  built from red code. It accepts a job as green from *any* run of that commit (a branch push and a
  tag push each produce one), and deliberately ignores upstream's cross-platform jobs — the freebsd
  one runs a third-party VM action that fails on its own infrastructure often enough to block
  releases while saying nothing about an Arch binary.
