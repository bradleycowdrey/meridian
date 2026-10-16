# dmgbuild settings for Meridian's installer window.
# Invoked by scripts/make-dmg.sh with -D app=… -D background=… -D icon=…
import os

app = defines["app"]
appname = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines.get("icon")  # volume icon shown in Finder and on the desktop
badge_icon = None

# Window: 660 × 400 content, matching Resources/dmg/background(@2x).png
background = defines["background"]
window_rect = ((200, 140), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0

# Icons sit centred on the tiles painted into the background.
arrange_by = None
icon_size = 128
text_size = 13
label_pos = "bottom"
icon_locations = {
    appname: (180, 205),
    "Applications": (480, 205),
}
