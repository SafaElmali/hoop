<p align="center"><img src="media/cover.png" alt="Hoop: throw files into your Mac's Trash" width="100%"></p>

# Hoop

A tiny macOS menu bar app that turns your Trash into a basketball hoop. Drag a file off your desktop, swing, let go: it flies with the momentum of your drag, and if it lands in the can it goes to the Trash.

▶️ **[Watch the demo on X](https://x.com/SafaElmali/status/2109359345699868825)**

## Play

- **⌃⌥H** (or 🏀 in the menu bar) turns on shoot mode: the Dock's Trash grows into a basket. **Esc** turns it off.
- Drag any file and let go mid-swing. In the can → Finder moves it to the Trash, just like dropping it on the Dock's Trash (so **Put Back** works), with **Undo** in the toast and the 🏀 menu.
- Miss → the file stays put. A desktop file's icon moves to where it landed.
- Drop a file straight onto the Trash for a dunk.
- Drag the Trash itself to put it anywhere; 🏀 → **Put Trash Back on Dock** resets it.

## Options (🏀 menu)

- **Mode**: Normal · Moving (the Trash glides back and forth) · Impossible (it dodges every shot)
- **Trash Size**: Small · Medium · Large · Huge · Dock Size (the real Trash in your Dock: its size, its spot)
- **Sound Effects**: whooshes, can clanks and landings; a make plays Finder's own trash sound

## Install

Needs macOS 14 or later and the Swift toolchain (Xcode or the Command Line Tools).

```bash
git clone https://github.com/SafaElmali/hoop.git
cd hoop
./build.sh
open build/Hoop.app
```

On first launch macOS asks for **Accessibility** (to find the Trash in the Dock). The first make asks to let Hoop **control Finder** (to trash files the way Finder does, and to move a missed file's icon to where it landed). The app is ad-hoc signed, so after a rebuild macOS may ask again.

## How it works

```
 Finder drag ──► drag pasteboard changes while the button is down
                       │  (polled 60×/s, only in shoot mode)
                       ▼
 OverlayWindow: full-screen, click-through panel ──arms──► becomes the drop target
                       │  dragging updates → fling velocity
                       ▼
 CourtScene (SpriteKit physics): file flies ──► inside the can? ──► FileManager.trashItem + Undo
                                                └─ miss ──► Finder moves the desktop icon there
 DockTrash (Accessibility API) ──► Trash tile frame ──► where the basket grows from
```

- `Sources/Hoop/`: the app (AppKit + SpriteKit, no dependencies).
- `Promo/` + `promo.sh`: renders the demo video and the cover from the game's own code (needs `ffmpeg`).

## License

MIT
