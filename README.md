<p align="center">
  <img src="Shine/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" alt="Shine icon">
</p>

<h1 align="center">Shine</h1>

<p align="center">
  Control the brightness and volume of external monitors from your Mac —<br>
  with your keyboard's brightness and volume keys, over DDC/CI.
</p>

---

## Features

- 🌞 **Brightness control** for third-party external monitors via DDC/CI
- 🔊 **Volume & mute control** for monitor speakers
- ⌨️ **Native keyboard keys** — the brightness keys adjust the monitor under your mouse pointer; the volume keys adjust the monitor your audio is playing through
- 🖥 **Multi-monitor aware** — displays are matched to their DDC ports by EDID, and volume keys follow the system's default audio output device
- 📊 **macOS-style on-screen HUD** when using the keys
- 🫥 Lives in the menu bar; the icon can be hidden entirely

## Requirements

- Apple Silicon Mac, macOS 14 (Sonoma) or later
- An external monitor connected over HDMI, DisplayPort, or USB-C with **DDC/CI enabled** (most monitors have it on by default; check the monitor's on-screen menu if controls don't respond)

> **Note:** Displays connected through some docks/adapters, and monitors in
> certain HDR/picture modes, may not accept DDC commands.

## Install

1. Download the latest `Shine-x.y.dmg` from [Releases](../../releases).
2. Drag **Shine** to **Applications** and open it.
3. macOS will warn that it *"could not verify Shine is free of malware"* — this
   is because the app is not notarized (notarization requires a paid Apple
   Developer membership; Shine is free and open source). To open it anyway:
   - Open **System Settings → Privacy & Security**, scroll down, and click
     **"Open Anyway"**, then confirm.
   - Or from Terminal: `xattr -d com.apple.quarantine /Applications/Shine.app`
4. Grant **Accessibility** permission when prompted (System Settings →
   Privacy & Security → Accessibility). This is required to capture the
   keyboard brightness/volume keys; the menu bar sliders work without it.

## Build from source

```sh
git clone https://github.com/ademayar/Shine.git
cd Shine
./scripts/make-dmg.sh   # builds Release and produces build/Shine-x.y.dmg
```

Or open `Shine.xcodeproj` in Xcode and run.

## How it works

Shine talks to monitors over the DDC/CI protocol (VESA MCCS): brightness is
VCP code `0x10`, speaker volume `0x62`, and mute `0x8D`. On Apple Silicon the
I2C channel is reached through the private `IOAVService` API, resolved at
runtime — the same approach used by [MonitorControl](https://github.com/MonitorControl/MonitorControl)
and [Lunar](https://github.com/alin23/Lunar). Media keys are intercepted with
a `CGEventTap`, which is why the Accessibility permission is needed.

Because a private API is involved, Shine can never be on the App Store — but
it is perfectly fine as a directly-distributed app.

## FAQ

**The volume keys change the HUD but I hear no difference.**
The keys control the speakers of the monitor that is the current audio output
device. Check System Settings → Sound → Output.

**Brightness keys still change my MacBook's screen.**
That's intentional: the keys target the display under the mouse pointer. Move
the pointer onto the external monitor first.

**Nothing responds at all.**
Enable DDC/CI in your monitor's on-screen menu, and try connecting the monitor
directly rather than through a dock.

## License

[MIT](LICENSE)
