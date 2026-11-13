# VoidStation packages

xbps package repository for [VoidStation](https://github.com/Panther92/VoidStation),
the Void Linux based media station for TVs. It holds what Void Linux itself does
not ship, or not in the shape VoidStation needs:

- **XLibre** – the X server VoidStation uses, with its drivers
  (templates taken over from [xlibre-void/xlibre](https://github.com/xlibre-void/xlibre), see `NOTICE.md`)
- **vs-chdman** – `chdman` from MAME on its own, without the whole emulator
- Mullvad, emulators and apps that upstream only offers as AppImage,
  Flatpak or `.deb`

Packages are built by GitHub Actions on top of a pinned commit of
[void-packages](https://github.com/void-linux/void-packages) and signed with
the repository key in `keys/`.

## License

The templates and scripts in this repository are MIT licensed (`LICENSE`).
The packaged software keeps its own license, stated in each template.
