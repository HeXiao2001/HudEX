# Layout of the drag-to-Applications window (used by script/make_package.sh
# through `dmgbuild`). Icon positions are in window coordinates.
import os

application = defines.get("app")          # noqa: F821
volume_name = defines.get("volume_name")  # noqa: F821

files = [application]
symlinks = {"Applications": "/Applications"}

background = "script/dmg-background.png"
window_rect = ((240, 220), (660, 420))
icon_size = 104
default_view = "icon-view"
show_icon_preview = False

# A plain window: just the picture and the two icons.
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
label_pos = "bottom"

icon_locations = {
    os.path.basename(application): (178, 196),
    "Applications": (482, 196),
}
