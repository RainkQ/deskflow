# Keep Cursor on Leave — Design Spec

Date: 2026-06-14
Status: Draft

## Overview

Add a global option that, when enabled, prevents the cursor from being hidden when the mouse leaves a PC's screen. The cursor stays visible at the edge position, so someone can manually operate that PC with its own mouse/keyboard.

## Motivation

When a Deskflow client screen is being controlled from the server, the client hides its cursor. If someone walks up to the client machine and tries to use its own mouse, the cursor is invisible. With this option, the cursor remains visible, enabling frictionless manual takeover.

## Design

### New Option

- **ID:** `kOptionKeepCursorOnLeave = OPTION_CODE("KCOL")`
- **Type:** Boolean (1 = keep cursor visible on leave, 0 = hide cursor as before)
- **Scope:** Global (applies to all screens)
- **Default:** false (existing behavior)

### Option Flow

```
GUI checkbox → ServerConfig::m_KeepCursorOnLeave
  → Config.cpp addOption("", kOptionKeepCursorOnLeave, value)
    → Server::sendOptions() → all clients (including primary)
      → PlatformScreen::setOptions() parses and stores as member
```

### File Changes

#### 1. OptionTypes.h
Add option ID:
```cpp
static const OptionID kOptionKeepCursorOnLeave = OPTION_CODE("KCOL");
```

#### 2. Config.cpp
- In the global options parsing section (around line 676), add:
  ```cpp
  addOption("", kOptionKeepCursorOnLeave, s.parseBoolean(value));
  ```
- In the option type classification methods, add `kOptionKeepCursorOnLeave` to the boolean group.

#### 3. Server.cpp
In `processOptions()`, add handling to set the option on the server's own platform screen (primary client). Currently `processOptions()` only sets server-internal state; it must also forward to `m_primaryClient->setOptions()` for completeness.

#### 4. OSXScreen.h / OSXScreen.mm
- Add `bool m_keepCursorOnLeave = false;` member
- `setOptions()`: parse `kOptionKeepCursorOnLeave` and store
- `leave()`: gate both `hideCursor()` AND `warpCursor()`:
  ```cpp
  if (!m_keepCursorOnLeave) {
    hideCursor();
    if (m_isPrimary) {
      avoidHesitatingCursor();
      warpCursor(m_xCenter, m_yCenter);
    }
  }
  m_isOnScreen = false;
  ```
- `enable()` (secondary path): gate `hideCursor()` + `fakeMouseMove(center)`
- `handleCGInputEventSecondary()`: gate `showCursor()` call

#### 5. MSWindowsDesks.h / MSWindowsDesks.cpp
- Add `bool m_keepCursorOnLeave = false;` member
- `setOptions()`: parse and store (follow pattern of `m_leaveForegroundOption`)
- `deskLeave()`: gate `setCursorVisibility(false)`, warp to center, and hider window `SetWindowPos`
- `enable()` secondary: gate cursor hiding

#### 6. XWindowsScreen.h / XWindowsScreen.cpp
- Add `bool m_keepCursorOnLeave = false;` member
- `setOptions()`: parse and store (follow pattern of `m_preserveFocus`)
- `leave()`: gate hider window logic (`XMoveWindow`/`XMapRaised`) + `XWarpPointer` + `XTestFakeMotionEvent`
- `enable()` secondary: gate hider window positioning + `fakeMouseMove(center)`
- Note: X11 uses a hider window overlay instead of a `hideCursor()` API call. The gating must skip `XMoveWindow`/`XMapRaised` for the hider, not a nonexistent function.

#### 7. ServerConfig.h
- Add `bool m_KeepCursorOnLeave = false;` member
- Add getter `keepCursorOnLeave()` and setter `setKeepCursorOnLeave(bool)`

#### 8. ServerConfig.cpp
- `commit()`: persist to QSettings
- `recall()`: load from QSettings
- `operator==`: include new member
- `operator<<`: serialize as `keepCursorOnLeave = true/false`
- `readSectionOptions()` or equivalent: parse from config

#### 9. ServerConfigDialog.ui
Add checkbox in the general settings section (near `cbRelativeMouseMoves`/`cbDefaultLockToScreenState`).

#### 10. ServerConfigDialog.cpp
- `loadFromConfig()`: set checkbox from `serverConfig().keepCursorOnLeave()`
- Add toggle slot connecting checkbox to `setKeepCursorOnLeave()`

### Edge Cases

1. **Toggling mid-session:** Option takes effect on next `leave()`/`enable()` call. No immediate show/hide trigger — acceptable.
2. **Protocol backward compatibility:** `kMsgDSetOptions` sends arbitrary `(OptionID, OptionValue)` pairs. Unknown options are silently ignored by clients. No protocol version bump needed.
3. **Local input on secondary:** If the secondary event tap is active and detects local mouse input, with this option the cursor is already visible, so `showCursor()` is a no-op. Gate prevents unnecessary work.
4. **Config file reload:** `setConfig()` calls both `processOptions()` and `sendOptions()`, so the option propagates on reload.

### Not in Scope

- Per-screen granularity (this is a global setting)
- Immediate cursor show/hide on settings change mid-session
