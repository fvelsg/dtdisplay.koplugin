# dtdisplay.koplugin (Fork)

A [koreader][1] plugin to display the time and day in a fullscreen widget with images allowed and some other functionalities.

## Motivation

E-ink screens make nice ambient displays. I thought it useful to show the time
and date when the device is charging.

Inspired by [clock.koplugin][2] and [kobo-display][3].

## Installation

Before installing it you install the https://github.com/fvelsg/autosuspend-fork.koplugin/ exactly in the way it's recommended. They're connected plugind.
Clone and copy this repository to the `koreader/plugins` folder.

## Usage

Navigate to `Plugins -> More tools -> Time & Day` to open the widget. Tap
anywhere on the screen to close the widget.

## Testing

Tested with Koreader 2023.03 "Cherry Blossom" on a Kobo Clara 2E and with the
Linux x86 Appimage.

[1]: https://github.com/koreader/koreader
[2]: https://github.com/jperon/clock.koplugin
[3]: https://github.com/RolandColored/kobo-display


----
next eteps:
- there should be a way to select the folders for each landscape and portrait pngs
- there should be a settings to select if the person wants the screen to full refresh each time it updates the png (not the clock)
- there should be a way to only get out of the widget when the user blocks the screen (optional)
- there should be a possibility to put the weather plugin showing up (optional)
