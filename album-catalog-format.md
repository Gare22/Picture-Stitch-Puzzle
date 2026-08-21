# Puzzle Album Catalog Format

This document specifies the JSON catalog that the **Picture Puzzle** Godot app fetches
at runtime to list downloadable albums. A web host serves this JSON file (plus the
referenced image files); the app downloads each album's **images** after the user
purchases the album (free albums download right away). Album covers rotate through the
downloaded images — no separate thumbnail is needed.

## Where the file lives

- The app requests a single JSON URL — the `album_catalog_url` set on the `LevelManager`
  autoload in the Godot project.
- Publish the catalog JSON at that URL, e.g.
  `https://your-host.example/puzzles/catalog.json`.
- Every URL inside it (`images`) must be an **absolute** `http(s)` URL and
  publicly reachable. The app downloads them as-is; it does not transform or resize them.

## Document shape

The file is either:

- a JSON **array** of album objects, **or**
- a JSON object with a single key `"albums"` whose value is that array.

## Album object

| Field                | Type            | Required | Notes                                                                 |
|----------------------|-----------------|----------|-----------------------------------------------------------------------|
| `id`                 | string          | yes      | Unique, filesystem-safe (letters/digits/`-`/`_`). Used as the local folder name and cache key. Duplicate `id`s are ignored. |
| `name`               | string          | no       | Display name on the album button. Defaults to `id` if omitted.        |
| `price`              | integer         | no       | Cost in coins. `0` (default) = free; free albums auto-download. Positive = paid (uses the in-app currency system). |
| `unlocked_by_default`| boolean         | no       | If `true`, treated as free regardless of `price`. Default `false`.    |
| `puzzle_count`       | integer         | no       | Number of puzzles in this album. Used by the client to detect when new puzzles are added to an existing album. Defaults to `images.size()` if omitted. |
| `previews`           | array of string | no       | Lower-resolution versions of `images`, one URL per image. Downloaded for **locked (paid, unpurchased)** albums so the cover can show grayed-out previews without giving away the full-res puzzles. If omitted, the full `images` are downloaded for locked covers instead. |
| `images`             | array of string | yes*     | Full puzzle images. Downloaded after purchase (or immediately if free). Each URL should end in the bare filename. The first image is used as the album cover and the cover rotates through all images. |

\*Required for a playable album. An album with no `images` will appear but have no puzzles.

## Example

```json
[
  {
    "id": "sunset",
    "name": "Sunsets",
    "price": 0,
    "puzzle_count": 3,
    "images": [
      "https://your-host.example/puzzles/sunset/1.png",
      "https://your-host.example/puzzles/sunset/2.png",
      "https://your-host.example/puzzles/sunset/3.png"
    ]
  },
  {
    "id": "cityscapes",
    "name": "Cityscapes",
    "price": 150,
    "puzzle_count": 2,
    "previews": [
      "https://your-host.example/puzzles/cityscapes/a_preview.jpg",
      "https://your-host.example/puzzles/cityscapes/b_preview.jpg"
    ],
    "images": [
      "https://your-host.example/puzzles/cityscapes/a.png",
      "https://your-host.example/puzzles/cityscapes/b.png"
    ]
  }
]
```

## Rules / gotchas

- **Unique `id`** — collisions are silently dropped.
- **Filenames** — the app derives each local file name from the URL's last path segment
  (`url.get_file()`). Use clean URLs ending in the real filename (e.g. `/sunset/1.png`);
  avoid query strings like `?v=2`, which would produce a bad filename.
- **HTTPS** — use `https://` for the catalog and all images (some platforms block
  mixed/HTTP content).
- **Reachability** — every `images` URL must return the actual image (PNG/JPG).
- **Free vs paid** — `price: 0` (or `unlocked_by_default: true`) makes the app download
  the full images automatically. `price > 0` means the user must purchase with in-app
  coins to play the album; the locked cover shows **grayed-out previews** downloaded
  from the optional `previews` array (or the full images if `previews` is omitted).
- **Smart sync** — the app fetches the catalog on every launch and compares `puzzle_count`
  against the cached album. If `puzzle_count` changed, the album is updated (missing images
  downloaded, levels re-registered). Albums no longer in the catalog are deleted. Already
  downloaded images are not re-downloaded.
- **Covers** — the first image in `images` is used as the album cover; the cover rotates
  through all images on a timer (same behavior as local albums).
- **Persistence** — once downloaded, images are cached on the device
  (`user://albums/<id>/`) and reused in future sessions. The catalog is re-fetched each
  launch to pick up new albums, but already-downloaded ones are not re-downloaded.
