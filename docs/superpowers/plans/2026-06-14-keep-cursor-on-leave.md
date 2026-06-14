# Keep Cursor on Leave — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a global option that keeps the cursor visible on a PC's screen when the mouse leaves it (moves to another shared PC), instead of hiding it.

**Architecture:** A new boolean option `kOptionKeepCursorOnLeave` flows from GUI checkbox → ServerConfig → config file → Server::sendOptions() → platform screen `setOptions()`. Each platform screen (macOS, Windows, Linux) stores `m_keepCursorOnLeave` and gates its cursor-hiding/cursor-warping logic in `leave()` and `enable()`.

**Tech Stack:** C++17, Qt 6, Cocoa (macOS), Win32 API, X11

---

### Task 1: Add option ID to OptionTypes.h

**Files:**
- Modify: `src/lib/deskflow/OptionTypes.h:61`

- [ ] **Step 1: Add the new option constant**

After line 61 (`static const OptionID kOptionClipboardSharingSize...`), add:

```cpp
static const OptionID kOptionKeepCursorOnLeave = OPTION_CODE("KCOL");
```

- [ ] **Step 2: Verify it compiles**

Run: `cmake --build build --target Deskflow deskflow-core 2>&1 | tail -5`
Expected: build succeeds (no references to `kOptionKeepCursorOnLeave` yet, so it's just an unused constant)

- [ ] **Step 3: Commit**

```bash
git add src/lib/deskflow/OptionTypes.h
git commit -m "feat: add kOptionKeepCursorOnLeave option ID

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Add config parsing and serialization in Config.cpp

**Files:**
- Modify: `src/lib/server/Config.cpp:676`

- [ ] **Step 1: Add parsing for the new option in global options**

After `src/lib/server/Config.cpp` line 676 (`addOption("", kOptionClipboardSharing, ...)`), add:

```cpp
} else if (name == "keepCursorOnLeave") {
  addOption("", kOptionKeepCursorOnLeave, s.parseBoolean(value));
```

- [ ] **Step 2: Add option name in getOptionName()**

After line 1260 (`if (id == kOptionClipboardSharingSize) { return "clipboardSharingSize"; }`), add:

```cpp
if (id == kOptionKeepCursorOnLeave) {
  return "keepCursorOnLeave";
}
```

- [ ] **Step 3: Add option value serialization in getOptionValue()**

On line 1271 (in the boolean options list), add `kOptionKeepCursorOnLeave` to the condition. Change:
```cpp
id == kOptionWin32KeepForeground || id == kOptionScreenPreserveFocus || id == kOptionClipboardSharing ||
    id == kOptionClipboardSharingSize) {
```
To:
```cpp
id == kOptionWin32KeepForeground || id == kOptionScreenPreserveFocus || id == kOptionClipboardSharing ||
    id == kOptionClipboardSharingSize || id == kOptionKeepCursorOnLeave) {
```

- [ ] **Step 4: Verify it compiles**

Run: `cmake --build build --target deskflow-core 2>&1 | tail -5`
Expected: build succeeds

- [ ] **Step 5: Commit**

```bash
git add src/lib/server/Config.cpp
git commit -m "feat: parse and serialize keepCursorOnLeave config option

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Add member + setOptions gating in OSXScreen (macOS)

**Files:**
- Modify: `src/lib/platform/OSXScreen.h:249`
- Modify: `src/lib/platform/OSXScreen.mm:924-929, 739-796, 867-879, 716-737`

- [ ] **Step 1: Add member variable to OSXScreen.h**

After line 249 (`bool m_cursorHidden;`), add:

```cpp
bool m_keepCursorOnLeave = false;
```

- [ ] **Step 2: Initialize in resetOptions()**

In `src/lib/platform/OSXScreen.mm`, in `resetOptions()` (line 924), add:

```cpp
void OSXScreen::resetOptions()
{
  m_keepCursorOnLeave = false;
}
```

- [ ] **Step 3: Parse in setOptions()**

Replace the stub `setOptions()` at line 929:
```cpp
void OSXScreen::setOptions(const OptionsList &)
{
  // no options are currently supported
}
```
With:
```cpp
void OSXScreen::setOptions(const OptionsList &options)
{
  for (uint32_t i = 0, n = options.size(); i < n; i += 2) {
    if (options[i] == kOptionKeepCursorOnLeave) {
      m_keepCursorOnLeave = (options[i + 1] != 0);
      LOG_VERBOSE("keep cursor on leave: %s", m_keepCursorOnLeave ? "true" : "false");
    }
  }
}
```

- [ ] **Step 4: Gate hideCursor() and warpCursor() in leave()**

Replace the `leave()` method (lines 867-879):
```cpp
void OSXScreen::leave()
{
  if (!m_keepCursorOnLeave) {
    hideCursor();

    if (m_isPrimary) {
      avoidHesitatingCursor();
      LOG_VERBOSE("centering cursor on leave: %+d, %+d", m_xCenter, m_yCenter);
      warpCursor(m_xCenter, m_yCenter);
    }
  }

  // now off screen
  m_isOnScreen = false;
}
```

- [ ] **Step 5: Gate hideCursor() and fakeMouseMove() in enable() (secondary path)**

In `enable()` (lines 756-763), wrap the hide + warp in the condition. Change:
```cpp
  } else {
    // FIXME -- prevent system from entering power save mode

    hideCursor();

    // warp the mouse to the cursor center
    fakeMouseMove(m_xCenter, m_yCenter);
```
To:
```cpp
  } else {
    // FIXME -- prevent system from entering power save mode

    if (!m_keepCursorOnLeave) {
      hideCursor();

      // warp the mouse to the cursor center
      fakeMouseMove(m_xCenter, m_yCenter);
    }
```

- [ ] **Step 6: Verify it compiles**

Run: `cmake --build build --target deskflow-core 2>&1 | tail -10`
Expected: build succeeds

- [ ] **Step 7: Commit**

```bash
git add src/lib/platform/OSXScreen.h src/lib/platform/OSXScreen.mm
git commit -m "feat(macOS): gate cursor hide/warp on leave when keepCursorOnLeave is set

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Add member + setOptions gating in MSWindowsDesks (Windows)

**Files:**
- Modify: `src/lib/platform/MSWindowsDesks.h:284`
- Modify: `src/lib/platform/MSWindowsDesks.cpp:181-198, 562-647, 139-169`

- [ ] **Step 1: Add member variable to MSWindowsDesks.h**

After line 284 (`bool m_relativeMouseMoves = false;`), add:

```cpp
bool m_keepCursorOnLeave = false;
```

- [ ] **Step 2: Initialize in resetOptions()**

In `src/lib/platform/MSWindowsDesks.cpp`, in `resetOptions()` (line 181), after `m_relativeMouseMoves = false;` add:

```cpp
m_keepCursorOnLeave = false;
```

- [ ] **Step 3: Parse in setOptions()**

In `setOptions()` (around line 197), after the `m_relativeMouseMoves` parsing, add:

```cpp
} else if (options[i] == kOptionKeepCursorOnLeave) {
  m_keepCursorOnLeave = (options[i + 1] != 0);
  LOG_VERBOSE("keep cursor on leave: %s", m_keepCursorOnLeave ? "true" : "false");
```

- [ ] **Step 4: Gate cursor hiding and warping in deskLeave()**

In `deskLeave()` (line 562), wrap the cursor-related operations in a condition. Change the beginning of the method:

```cpp
void MSWindowsDesks::deskLeave(Desk *desk, HKL keyLayout)
{
  if (!m_isPrimary && m_relativeMouseMoves) {
    saveRelativeRestorePosition(desk);
  }

  if (!m_keepCursorOnLeave) {
    setCursorVisibility(false);

    if (m_isPrimary) {
      // ... (all primary path code: SetWindowPos, ActivateKeyboardLayout,
      //      SetActiveWindow, EnableWindow, SetForegroundWindow, etc.)
    } else {
      // move hider window under the cursor center, raise, and show it
      SetWindowPos(desk->m_window, HWND_TOP, m_xCenter, m_yCenter, 1, 1, SWP_NOACTIVATE | SWP_SHOWWINDOW);

      // watch for mouse motion...
      SetCapture(desk->m_window);

      LOG_VERBOSE("centering cursor on leave: %+d,%+d", m_xCenter, m_yCenter);
      ARCH->sleep(0.03);
      deskMouseMove(m_xCenter, m_yCenter);
    }
  }
}
```

The entire body of `deskLeave()` after the `saveRelativeRestorePosition` call should be wrapped in `if (!m_keepCursorOnLeave) { ... }`.

- [ ] **Step 5: Verify it compiles**

Run: `cmake --build build --target deskflow-core 2>&1 | tail -10`
Expected: build succeeds

- [ ] **Step 6: Commit**

```bash
git add src/lib/platform/MSWindowsDesks.h src/lib/platform/MSWindowsDesks.cpp
git commit -m "feat(Windows): gate cursor hide/warp on leave when keepCursorOnLeave is set

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Add member + setOptions gating in XWindowsScreen (Linux)

**Files:**
- Modify: `src/lib/platform/XWindowsScreen.h:231`
- Modify: `src/lib/platform/XWindowsScreen.cpp:395-412, 186-204, 287-340`

- [ ] **Step 1: Add member variable to XWindowsScreen.h**

After line 231 (`bool m_preserveFocus = false;`), add:

```cpp
bool m_keepCursorOnLeave = false;
```

- [ ] **Step 2: Initialize in resetOptions()**

In `resetOptions()` (line 395), add after `m_preserveFocus = false;`:

```cpp
m_keepCursorOnLeave = false;
```

- [ ] **Step 3: Parse in setOptions()**

In `setOptions()` (line 401), after the `m_preserveFocus` parsing block, add:

```cpp
} else if (options[i] == kOptionKeepCursorOnLeave) {
  m_keepCursorOnLeave = (options[i + 1] != 0);
  LOG_VERBOSE("keep cursor on leave: %s", m_keepCursorOnLeave ? "true" : "false");
```

- [ ] **Step 4: Gate hider window and cursor warp in enable() (secondary path)**

In `enable()` (lines 195-203), wrap the hider window logic. Change:
```cpp
    // move hider window under the cursor center
    XMoveWindow(m_display, m_window, m_xCenter, m_yCenter);

    // raise and show the window
    // FIXME -- take focus?
    XMapRaised(m_display, m_window);

    // warp the mouse to the cursor center
    fakeMouseMove(m_xCenter, m_yCenter);
```
To:
```cpp
    if (!m_keepCursorOnLeave) {
      // move hider window under the cursor center
      XMoveWindow(m_display, m_window, m_xCenter, m_yCenter);

      // raise and show the window
      // FIXME -- take focus?
      XMapRaised(m_display, m_window);

      // warp the mouse to the cursor center
      fakeMouseMove(m_xCenter, m_yCenter);
    }
```

- [ ] **Step 5: Gate hider window and cursor warp in leave()**

In `leave()` (lines 287-340), gate the hider window and warp logic:

```cpp
void XWindowsScreen::leave()
{
  if (!m_isPrimary) {
    // restore the previous keyboard auto-repeat state.
    if (m_autoRepeat) {
      // XAutoRepeatOn(m_display);
    }

    // move hider window under the cursor center
    if (!m_keepCursorOnLeave) {
      XMoveWindow(m_display, m_window, m_xCenter, m_yCenter);
    }
  }

  if (!m_keepCursorOnLeave) {
    // raise and show the window
    XMapRaised(m_display, m_window);

    // grab the mouse and keyboard, if primary and possible
    if (m_isPrimary && !grabMouseAndKeyboard()) {
      XUnmapWindow(m_display, m_window);
    }

    // now warp the mouse.
    if (m_isPrimary) {
      warpCursor(m_xCenter, m_yCenter);
    } else {
      XTestFakeMotionEvent(m_display, DefaultScreen(m_display), m_xCenter, m_yCenter, CurrentTime);
      XFlush(m_display);
    }
  }

  // save current focus
  XGetInputFocus(m_display, &m_lastFocus, &m_lastFocusRevert);

  // take focus
  if (m_isPrimary || !m_preserveFocus) {
    XSetInputFocus(m_display, m_window, RevertToPointerRoot, CurrentTime);
  }

  // set input context focus to our window
  if (m_ic != nullptr) {
    XmbResetIC(m_ic);
    XSetICFocus(m_ic);
    m_filtered.clear();
  }

  // now off screen
  m_isOnScreen = false;
}
```

Key: `XGetInputFocus`, `XSetInputFocus`, and `XSetICFocus` remain outside the gate — they manage keyboard focus, not cursor visibility.

- [ ] **Step 6: Verify it compiles**

Run: `cmake --build build --target deskflow-core 2>&1 | tail -10`
Expected: build succeeds

- [ ] **Step 7: Commit**

```bash
git add src/lib/platform/XWindowsScreen.h src/lib/platform/XWindowsScreen.cpp
git commit -m "feat(Linux): gate cursor hide/warp on leave when keepCursorOnLeave is set

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: Add GUI config support in ServerConfig

**Files:**
- Modify: `src/lib/gui/config/ServerConfig.h:93,198`
- Modify: `src/lib/gui/config/ServerConfig.cpp:55-67, 101-108, 147-158, 251-253`

- [ ] **Step 1: Add getter/setter and member to ServerConfig.h**

Add getter after line 92 (`clipboardSharingSize()`):
```cpp
  bool keepCursorOnLeave() const
  {
    return m_KeepCursorOnLeave;
  }
```

Add setter in the private section (around line 160, near other setters):
```cpp
  void setKeepCursorOnLeave(bool on)
  {
    m_KeepCursorOnLeave = on;
  }
```

Add member after line 197 (`m_ClipboardSharingSize`):
```cpp
  bool m_KeepCursorOnLeave = false;
```

- [ ] **Step 2: Add to operator==**

In `operator==()` (line 53), add the comparison before the closing `;`:
```cpp
         m_ClipboardSharingSize == sc.m_ClipboardSharingSize &&       //
         m_KeepCursorOnLeave == sc.m_KeepCursorOnLeave;
```

- [ ] **Step 3: Add to commit()**

In `commit()` (line 92), after the `clipboardSharingSize` line, add:
```cpp
  settings().setValue("keepCursorOnLeave", keepCursorOnLeave());
```

- [ ] **Step 4: Add to recall()**

In `recall()` (line 134), after the `setClipboardSharing` line, add:
```cpp
  setKeepCursorOnLeave(settings().value("keepCursorOnLeave", false).toBool());
```

- [ ] **Step 5: Add to operator<< (config file serialization)**

In `operator<<()` (line 203), after the `clipboardSharingSize` output (around line 255), add:
```cpp
  outStream << "\t"
            << "keepCursorOnLeave = " << (config.keepCursorOnLeave() ? "true" : "false") << Qt::endl;
```

- [ ] **Step 6: Verify it compiles**

Run: `cmake --build build --target Deskflow 2>&1 | tail -10`
Expected: build succeeds

- [ ] **Step 7: Commit**

```bash
git add src/lib/gui/config/ServerConfig.h src/lib/gui/config/ServerConfig.cpp
git commit -m "feat(gui): add keepCursorOnLeave to ServerConfig

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: Add checkbox to ServerConfigDialog UI

**Files:**
- Modify: `src/lib/gui/dialogs/ServerConfigDialog.ui:453`

- [ ] **Step 1: Add checkbox widget after cbRelativeMouseMoves**

In `ServerConfigDialog.ui`, after the `cbRelativeMouseMoves` widget (ends around line 453), add:

```xml
          <item>
           <widget class="QCheckBox" name="cbKeepCursorOnLeave">
            <property name="enabled">
             <bool>true</bool>
            </property>
            <property name="text">
             <string>Keep cursor &amp;visible when mouse leaves screen</string>
            </property>
           </widget>
          </item>
```

- [ ] **Step 2: Add tabstop entry**

In the `<tabstops>` section (around line 1075), add after `cbRelativeMouseMoves`:

```xml
  <tabstop>cbKeepCursorOnLeave</tabstop>
```

- [ ] **Step 3: Verify the UI compiles**

Run: `cmake --build build --target Deskflow 2>&1 | tail -10`
Expected: build succeeds (the UI file gets processed by `uic`)

- [ ] **Step 4: Commit**

```bash
git add src/lib/gui/dialogs/ServerConfigDialog.ui
git commit -m "feat(gui): add keep cursor on leave checkbox to server config dialog

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: Wire up the checkbox in ServerConfigDialog.cpp

**Files:**
- Modify: `src/lib/gui/dialogs/ServerConfigDialog.h:110`
- Modify: `src/lib/gui/dialogs/ServerConfigDialog.cpp:390, 464, 494`

- [ ] **Step 1: Add load in loadFromConfig()**

After line 390 (`ui->cbWin32KeepForeground->setChecked(serverConfig().win32KeepForeground());`), add:

```cpp
  ui->cbKeepCursorOnLeave->setChecked(serverConfig().keepCursorOnLeave());
```

- [ ] **Step 2: Add connect in initConnections()**

After the `cbRelativeMouseMoves` connect (around line 475), add:

```cpp
  connect(ui->cbKeepCursorOnLeave, &QCheckBox::toggled, this, [this](bool enabled) {
    serverConfig().setKeepCursorOnLeave(enabled);
    onChange();
  });
```

- [ ] **Step 3: Verify it compiles**

Run: `cmake --build build --target Deskflow 2>&1 | tail -10`
Expected: build succeeds

- [ ] **Step 4: Commit**

```bash
git add src/lib/gui/dialogs/ServerConfigDialog.h src/lib/gui/dialogs/ServerConfigDialog.cpp
git commit -m "feat(gui): wire keep cursor on leave checkbox to ServerConfig

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Final Verification

- [ ] **Full build:**

```bash
cmake --build build --target Deskflow deskflow-core app_translations 2>&1 | tail -10
```
Expected: all targets build successfully

