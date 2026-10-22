# Watch face format (v1)

A watch face is a small binary file (`.wf`, usually under 1 KB) that describes a background and a list of
elements. The phone builds faces in its editor and uploads them; the watch draws them, and the user swipes left
and right between the installed faces. Uploading, ordering and deleting faces is covered by
[watch-ble-protocol.md](watch-ble-protocol.md) §12.

The reference implementation is the Swift package **WatchFaceKit**
(`components/watch_faces/WatchFaceKit`). The watch firmware (Embedded Swift) and the iOS app compile the same
sources, so the model, the codec, the hand geometry and the texts are identical on both. Use it rather than
re-implementing this document. `swift test` checks the codec, including the exact bytes of a small face. `swift run wfce` writes,
dumps and renders face files (`wfce render klassisk out.png`) and rasterizes fonts. The rendering and rasterizing
use `WatchFaceGraphics`, the package's Core Graphics/Core Text target, which the app also uses for its preview.

## 1. Coordinates and units

- Pixels on the watch screen, 410 × 502. The origin is the top left corner, and y grows downwards.
- Angles of the clock are clockwise from 12 o'clock.
- Colours are RGBA, 8 bits per channel. Alpha 255 is opaque.

## 2. Encoding

```
file   = "WFCE" version(1 byte, = 1) record*
record = tag(varint) length(varint) payload(length bytes)
```

- **varint:** unsigned LEB128 (7 bits per byte, least significant group first, high bit = more bytes follow).
- **Payload types** used in the tables below:

| Type | Payload |
|---|---|
| uint | varint |
| sint | zigzag varint (`(n << 1) ^ (n >> 31)`) |
| bool | uint, 0 or 1 |
| color | 4 bytes: r g b a |
| string | UTF-8 bytes, no NUL |
| nested | a sequence of records |

**Variant records:** a record whose payload holds exactly one record. The inner tag selects the kind. Background
and element records work this way.

## 3. Extending the format

These rules are what keep old and new versions compatible:

- **Unknown tags are skipped.** A reader starts every structure from its defaults and only overwrites the fields
  it finds.
- New fields get new tags. A new field's default must reproduce the old behaviour.
- New element or background kinds get new variant tags.
  - An older watch skips an unknown element and draws an unknown background as black.
  - WatchFaceKit keeps unknown variants as `.unknown(tag, payload)`, so an older app can still edit a newer face
    without losing them. Unknown fields *inside* known elements are dropped on re-encoding.
- Never renumber a tag, reuse a tag, or change a tag's type.
- Bump the version byte only for a change old readers must reject.
- An enum value a reader doesn't know means the default (e.g. an unknown hand shape is drawn `rounded`).
- Features that need firmware support (an element that shows data, like the planned sunrise/sunset curve) get a
  feature name in `FaceFeature.all`.
  - The watch lists the features it supports in DEVICE_INFO.
  - The app compares them with `FaceFeature.required(by:)` and warns before uploading a face the watch can't draw.

## 4. Records

### Face (top level)

| Tag | Field | Type | Notes |
|---|---|---|---|
| 1 | id | string | 1–31 characters `A–Z a–z 0–9 _ -`. Same as the file id; a face whose id is a builtin's replaces it |
| 2 | name | string | Shown when swiping to the face; up to 63 bytes |
| 3 | background | variant | Default: black |
| 4 | element | variant | Repeated, at most 32. Drawn in order: later elements are on top |

### Shared structures

| Structure | Tag | Field | Type | Default |
|---|---|---|---|---|
| Placement | 1 | x | sint | 0 |
| | 2 | y | sint | 0 |
| | 3 | anchor | uint: 0 topLeading, 1 top, 2 topTrailing, 3 leading, 4 center, 5 trailing, 6 bottomLeading, 7 bottom, 8 bottomTrailing | center |
| FontRef | 1 | builtin size | uint | 20 |
| | 2 | asset id | string | — |
| TextStyle | 1 | font | FontRef | builtin 20 |
| | 2 | color | color | white |
| | 3 | letter spacing | sint | 0 |
| GradientStop | 1 | color | color | black |
| | 2 | location | uint 0–255 | 0 |

- **Placement:** (x, y) is where the `anchor` point of the element's bounding box goes. Text is also aligned
  left, center or right to match the anchor.
- **FontRef:** set one of the two tags.
  - Builtin sizes are Montserrat at 8–44 (even sizes), plus 66, a condensed font with ASCII only. Other sizes
    use the nearest one.
  - An asset font is an LVGL binfont. Glyphs it lacks fall back to Montserrat.

### Backgrounds (variant tags)

| Tag | Kind | Fields |
|---|---|---|
| 1 | color | the payload is a color |
| 2 | linearGradient | 1 stop (GradientStop, repeated, ≤ 8), 2 angle (uint degrees, CSS convention: 180 = top → bottom; default 180) |
| 3 | radialGradient | 1 stop (repeated), 2 centerX (sint), 3 centerY (sint), 4 radius (uint) |
| 4 | pattern | 1 kind (uint: 0 stripes, 1 diagonalStripes, 2 dots, 3 checker, 4 grid), 2 foreground (color), 3 background (color), 4 spacing (uint 4–64, default 16), 5 size (uint 1–64, default 2) |
| 5 | image | 1 asset id (string: a 410 × 502 PNG or baseline JPEG face asset), 2 fallback (color, shown until the image is ready), 3 dim (uint 0–100 %: a black layer over the image; default 0) |

**Image backgrounds:** the watch converts the image once, on first use, into a raw RGB565 file in `/store/cache`.
This takes about a second, and the fallback colour shows meanwhile.

Supported PNGs:
- non-interlaced
- 8 bits per sample
- greyscale, RGB, palette, grey+alpha or RGBA

Alpha is blended over the fallback colour.

### Elements (variant tags)

| Tag | Kind | Fields |
|---|---|---|
| 1 | digitalTime | 1 placement, 2 style (TextStyle), 3 hourFormat (uint: 0 24 h, 1 12 h), 4 showSeconds (bool), 5 leadingZero (bool, default true) |
| 2 | date | 1 placement, 2 style, 3 format (uint, see below), 4 uppercase (bool) |
| 3 | analogClock | see below |
| 4 | steps | 1 placement, 2 style (uint: 0 text, 1 ring), 3 text (TextStyle), 4 goal (uint, default 6000), 5 radius, 6 ringWidth, 7 ringColor, 8 trackColor |
| 5 | battery | 1 placement, 2 style (uint: 0 text "87%", 1 bar), 3 text (TextStyle; also the bar's colour) |
| 6 | text | 1 placement, 2 style, 3 text (string) |

**Date formats** (Danish; uppercase variants are spelled out on both sides):

| Value | Format | Example |
|---|---|---|
| 0 | weekdayDayMonth | "Tir 20. okt." |
| 1 | dayMonth | "20. okt." |
| 2 | weekday | "Tirsdag" |
| 3 | numeric | "20/10" |
| 4 | weekdayDay | "Tir 20" |

**Steps ring:** the bounding box is 2·radius square.

**analogClock:**

| Tag | Field | Type | Default |
|---|---|---|---|
| 1 | centerX | sint | 205 |
| 2 | centerY | sint | 251 |
| 3 | radius | uint | 190 |
| 4 | dial | nested: 1 fill (color, alpha 0 = none), 2 borderColor, 3 borderWidth (uint) | no fill, no border |
| 5 | ticks | nested: 1 mode (uint: 0 hidden, 1 hours, 2 hours and minutes), 2 major (TickStyle), 3 minor (TickStyle), 4 inset (uint, from the dial edge) | hidden |
| 6 | numerals | nested: 1 mode (uint: 0 hidden, 1 all, 2 every third (12, 3, 6, 9), 3 custom), 2 mask (uint, custom: bit n = hour n, bit 0 = 12), 3 style (TextStyle), 4 inset (uint, dial edge to numeral centre), 5 roman (bool) | hidden |
| 7 | hand | nested, repeated (≤ 4), drawn in order | — |
| 8 | capRadius | uint (0 = no cap) | 0 |
| 9 | capColor | color | white |

TickStyle: 1 length (uint), 2 width (uint), 3 color.

**hand:**

| Tag | Field | Type | Default |
|---|---|---|---|
| 1 | kind | uint: 0 hour, 1 minute, 2 second | hour |
| 2 | shape | uint: 0 line, 1 rounded, 2 tapered, 3 sword, 4 arrow, 5 lollipop | rounded |
| 3 | length | uint (centre to tip) | 100 |
| 4 | tail | uint (past the centre) | 0 |
| 5 | width | uint 1–64 | 6 |
| 6 | color | color | white |
| 7 | smooth | bool: second hand sweeps (10 updates/s) instead of ticking | false |

Shapes are defined by `HandGeometry.polygons(for:)`. The watch rasterizes them into anti-aliased 8-bit masks
(`HandMask`) and rotates them.

## 5. Builtin faces

`WatchFace.builtins` are always present on the watch: `klassisk`, `digital` and `blandet`. The phone can:
- hide or reorder them (SetFaceOrder)
- replace one by uploading a face with the same id
- copy one as a starting point
