# App icon

`Support/AppIcon.icns` is the icon the `make bundle` step copies into `Brow.app/Contents/Resources`
(`CFBundleIconFile` = `AppIcon` in `Support/Info.plist`).

- `Brow-AppIcon.svg`: the source, 1024 × 1024 on the macOS icon grid (824 pt squircle, 100 pt margin).
- `Brow-AppIcon-small.svg`: the simpler version used at 16 and 32 px (ring only).
- `AppIcon.iconset/`: every size as PNG.

To rebuild the `.icns` from the iconset on a Mac:

    iconutil -c icns Support/AppIcon/AppIcon.iconset -o Support/AppIcon.icns
