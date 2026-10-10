# ms_spy

`ms_spy` is the native cursor spy for the Window Monitor Data tab. It samples
the cursor position, the pixel colour under it and the accessibility element
under it on its own thread, and prints a line only when something changed. The
host runs it only while the Data tab is visible, so the Lua timer does no
inspection work.

On Windows it reads the pixel with `GetDC` and `GetPixel`, and the element with
one UI Automation `ElementFromPointBuildCache` call that caches control type,
localized control type, name, automation id, bounding rectangle, value and the
password flag. Values of password fields are never sent. Other platforms build
and report `unsupported`, and the Lua inspection path stays in charge.

## Layout

```
src/main.rs                 stdin command loop
src/protocol.rs             wire types and text truncation
src/platform/windows.rs     UI Automation backend
src/platform/unsupported.rs every other OS: reports "unsupported"
```

## Build and install

```
cd native/ms_spy
cargo test
cargo build --release
```

On Windows copy `target\release\ms_spy.exe` to `~/.local/bin/ms_spy.exe`.
`deploy_mudscript.ps1` in mudspoon builds and installs it.
`mac/lib/core/native_spy.lua` starts the daemon on demand when that file
exists.

## Protocol

Newline-delimited JSON. Commands go to stdin with a `"c"` tag and events come
out of stdout with a `"t"` tag. The daemon exits when stdin closes.

Commands:

```
{"c":"config","interval_ms":50}
{"c":"pause"}
{"c":"resume"}
{"c":"quit"}
```

- `interval_ms`: sample period, default 50, minimum 10
- every command except `quit` makes the next sample emit again
- `pause`: stops sampling until `resume`

Events:

| Event | Meaning |
| --- | --- |
| `{"t":"ready","version":"0.1.0","platform":"windows"}` | sampling has started |
| `{"t":"spy","sx":10,"sy":20,"pixel":{...},"element":{...}}` | the cursor, pixel or element changed |
| `{"t":"warn","msg":"..."}` | a bad command line was skipped |
| `{"t":"error","msg":"unsupported"}` | the backend cannot run, the daemon exits |

A `spy` event carries:

- `sx`, `sy`: cursor position in logical points
- `pixel`: `{"r":21,"g":21,"b":21,"hex":"#151515"}`, absent when unreadable
- `element`: absent when nothing is under the cursor, otherwise any of `role`,
  `roleDescription`, `title`, `value`, `identifier` and `frame`
  (`{"x":0,"y":0,"w":10,"h":10}`) using the same names as the Lua inspector

Strings longer than 120 characters are cut and end with `...`. Frames are
floored to whole points.

## Coordinates

The daemon is per-monitor DPI aware (v2) and reads physical pixels. It divides
every coordinate by the system DPI scale (`GetDpiForSystem() / 96`), which is
the same factor mudspoon uses in `hs.dpiscale` and `hs.screen`, so `sx`, `sy`
and `frame` match `hs.mouse.absolutePosition()` and `hs.window:frame()`.

While the cursor is still, the element is read again every 250 ms so changes in
the element under a still cursor are reported.

## Role mapping

UI Automation control types map to the closest macOS accessibility role. An
unlisted id becomes `AX<id>`. Keep `CONTROL_TYPE_ROLE` in mudspoon
`hs/uia.lua` on the same table.

| Id | Control type | Role |
| --- | --- | --- |
| 50000 | Button | AXButton |
| 50001 | Calendar | AXGroup |
| 50002 | CheckBox | AXCheckBox |
| 50003 | ComboBox | AXComboBox |
| 50004 | Edit | AXTextField |
| 50005 | Hyperlink | AXLink |
| 50006 | Image | AXImage |
| 50007 | ListItem | AXCell |
| 50008 | List | AXList |
| 50009 | Menu | AXMenu |
| 50010 | MenuBar | AXMenuBar |
| 50011 | MenuItem | AXMenuItem |
| 50012 | ProgressBar | AXProgressIndicator |
| 50013 | RadioButton | AXRadioButton |
| 50014 | ScrollBar | AXScrollBar |
| 50015 | Slider | AXSlider |
| 50016 | Spinner | AXIncrementor |
| 50017 | StatusBar | AXGroup |
| 50018 | Tab | AXTabGroup |
| 50019 | TabItem | AXRadioButton |
| 50020 | Text | AXStaticText |
| 50021 | ToolBar | AXToolbar |
| 50022 | ToolTip | AXHelpTag |
| 50023 | Tree | AXOutline |
| 50024 | TreeItem | AXRow |
| 50025 | Custom | AXGroup |
| 50026 | Group | AXGroup |
| 50027 | Thumb | AXHandle |
| 50028 | DataGrid | AXTable |
| 50029 | DataItem | AXRow |
| 50030 | Document | AXTextArea |
| 50031 | SplitButton | AXMenuButton |
| 50032 | Window | AXWindow |
| 50033 | Pane | AXGroup |
| 50034 | Header | AXGroup |
| 50035 | HeaderItem | AXButton |
| 50036 | Table | AXTable |
| 50037 | TitleBar | AXGroup |
| 50038 | Separator | AXSplitter |
| 50039 | SemanticZoom | AXGroup |
| 50040 | AppBar | AXToolbar |
