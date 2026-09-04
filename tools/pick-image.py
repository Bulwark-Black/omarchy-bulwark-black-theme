#!/usr/bin/env python3
"""Open a native "choose an image" dialog and print the chosen path.

Prints nothing and exits 1 if the user cancels.

Why not omarchy-menu-images: that is a grid of *wallpapers* from directories you
name, which is the wrong shape for "pick my logo, wherever it lives" — and on a
machine whose ~/Pictures holds no top-level images it simply shows an empty
grid. This is a real file chooser, so the logo can come from anywhere.

Uses GTK4's Gtk.FileDialog, which routes through the xdg-desktop-portal
FileChooser on Wayland.
"""

import sys

try:
    import gi
    gi.require_version("Gtk", "4.0")
    from gi.repository import Gtk, Gio, GLib
except (ImportError, ValueError) as exc:  # pragma: no cover
    print("python-gobject with GTK 4 is required: %s" % exc, file=sys.stderr)
    sys.exit(2)

chosen = {"path": None}


def on_activate(app):
    dialog = Gtk.FileDialog()
    dialog.set_title("Choose a logo image")
    dialog.set_modal(True)

    images = Gtk.FileFilter()
    images.set_name("Images")
    for mime in ("image/png", "image/jpeg", "image/webp",
                 "image/svg+xml", "image/tiff"):
        images.add_mime_type(mime)
    every = Gtk.FileFilter()
    every.set_name("All files")
    every.add_pattern("*")

    filters = Gio.ListStore.new(Gtk.FileFilter)
    filters.append(images)
    filters.append(every)
    dialog.set_filters(filters)
    dialog.set_default_filter(images)

    def finished(dlg, result):
        try:
            gfile = dlg.open_finish(result)
            if gfile is not None:
                chosen["path"] = gfile.get_path()
        except GLib.Error:
            pass  # cancelled or dismissed
        finally:
            app.release()

    app.hold()
    dialog.open(None, None, finished)


def main():
    app = Gtk.Application(application_id="com.bulwarkblack.logopicker",
                          flags=Gio.ApplicationFlags.NON_UNIQUE)
    app.connect("activate", on_activate)
    app.run([])
    if not chosen["path"]:
        sys.exit(1)
    print(chosen["path"])


if __name__ == "__main__":
    main()
