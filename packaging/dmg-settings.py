from pathlib import Path

root = Path.cwd()
format = "UDZO"
files = [(str(root / "dist/MouseWheelFix.app"), "Dalbear.app")]
symlinks = {"Applications": "/Applications"}
background = str(root / ".build/dalbear-dmg-background.tiff")
icon = str(root / "dist/MouseWheelFix.app/Contents/Resources/Dalbear.icns")
icon_locations = {"Dalbear.app": (175, 210), "Applications": (485, 210)}
window_rect = ((180, 160), (660, 472))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
icon_size = 96
text_size = 13
include_icon_view_settings = True
