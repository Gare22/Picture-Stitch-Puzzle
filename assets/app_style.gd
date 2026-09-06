class_name AppStyle
extends Resource

## Unified static style values for the Picture Puzzle UI.
## Open res://assets/app_style.tres in the editor to restyle the app.

## Horizontal gap (px) between the selection grid and the screen edges.
@export var grid_edge_gap: float = 8.0

## Number of columns in the selection grids.
@export var grid_columns: int = 2

## Gap (px) between album cover cells in the album grid.
@export var album_grid_separation: float = 8.0

## Gap (px) between puzzle buttons in the level grid.
@export var level_grid_separation: float = 5.0

## Corner radius (px) of the album cover thumbnails.
@export var album_corner_radius: float = 12.0

## Max width (px) of the album/level grid content. The logical viewport grows
## with the window (stretch mode "expand"), so on desktop fullscreen the grids
## would stretch comically wide; this caps the width budget used to compute
## cell sizes. 0 disables the cap.
@export var max_content_width: float = 900.0
