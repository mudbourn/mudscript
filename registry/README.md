# Package Registry Index

`index.json` is the registry: one in-tree, signed document listing every
publishable package. Binaries are **not** kept here - each entry points at a
release asset. The index stays small enough to review in a diff.

The client is `mac/lib/ms_registry.lua`. It fetches this file from the default
branch, verifies the signature, and caches it. It never installs; it hands
paths to `ms.package.install`.

## Entry shape

```json
{
  "id":          "aurora-theme",
  "type":        "theme",
  "name":        "Aurora",
  "version":     "1.2.0",
  "author":      "mudbourn",
  "description": "Cool-toned dark theme.",
  "website":     "https://github.com/mudbourn/mudscript",
  "sha256":      "<64-hex sha256 of the .mspkg>",
  "url":         "https://github.com/mudbourn/mudscript/releases/download/v1.2.0/aurora.mspkg",
  "size":        20481,
  "requires":    "1.4.0",
  "trust":       "trusted"
}
```

Rules the client enforces when reading an entry. **A row failing any of these
rejects the entire index**, exactly as a bad signature does - a skipped row
would fail invisibly, leaving a package missing from the library with no way to
tell whether that was intended. Validate before signing:

- `sha256` must be 64 hex characters. It is checked against the downloaded
  bytes before the path is handed back.
- `type` must be a known `ms.package` type (`macro`, `theme`, `sound`,
  `plugin`, `profile`).
- `url` must be `https` on a GitHub host. An index entry is data, not
  instruction; it cannot redirect the downloader anywhere else.
- `trust` is `"trusted"` only for author-published packages. Anything else,
  including a missing field, reads as `"community"`.
- `id` and `sha256` must each be unique. A duplicate is ambiguous about which
  row's trust applies, so it is rejected rather than resolved by ordering.

`ms.registry.status().error` names the offending row, so a rejected index says
which entry broke it.

## The plugin contract

Plugins are the only package type that is code, and the only one that cannot be
undone by rewriting a file. Two rules, both checked at review, both load-bearing
for the Plugins panel's off switch:

**1. Register through `ms`, not through `hs`.** Binds, bus subscriptions, key
and mouse callbacks, settings and tools definitions all go through the `ms`
handed to the plugin. That `ms` is a per-plugin proxy (`mac/lib/ms_plugins.lua`)
that records how to undo every registration it sees, which is what lets the
panel switch a plugin off without a reload. A plugin calling `hs.hotkey.bind`,
`hs.timer.new` or `hs.eventtap.new` directly registers with Hammerspoon instead,
where nothing can reach it - it will keep firing after the user switches it off,
and the off switch will have lied. Nothing in-process can detect this; review is
the only gate.

**2. Implement `:stop()`.** Anything a plugin holds that mudscript never saw -
its own state, tasks, watchers, anything created before it reached `ms` - is
only reachable through the Spoon's own teardown. `unload` calls `:stop()` first,
before replaying the recorded undo list, precisely because it is the only step
that knows about the parts this system does not.

A plugin that satisfies both can be enabled and disabled freely at runtime. One
that satisfies neither is not a plugin that can be turned off, whatever the
toggle says.

## Publishing

Merging an edit does not publish it. An index that lands on `main` still
carries the previous signature, which no longer covers it, so the client
discards it whole and every install falls back to zero entries. **An edit is
live only once it has been re-signed.**

Steps 1-2 are automated by `mac/bin/registry_publish.sh`, which uploads the
asset, derives the row from the package's own `mspkg.json`, and validates the
result - so a row cannot disagree with the bytes it points at:

```bash
bash mac/bin/registry_publish.sh path/to/aurora.mspkg
# --id <slug>       pin the registry id (default: a type-name slug)
# --release <tag>   release holding the asset (default: packages)
# --dry-run         print the row and touch nothing
```

Re-running on a package whose id is already listed **updates** that entry -
re-uploads the asset and refreshes `sha256`/`size`/`version` from the new
bytes. That is how a version bump ships; no flag is needed. The command prints
the `v... -> v...` transition so an update is never a silent overwrite.

It leaves the index **unsigned** on purpose; step 3 still signs. Doing it by
hand instead:

1. Upload the `.mspkg` as a release asset and note its `sha256` and size.
2. Add the row to `entries` and commit. Push validation runs on every change
   to this file - check it before assuming the edit is good.
3. Run the **Sign Registry** workflow from the Actions tab with *sign*
   checked. It validates, signs, verifies its own signature against the key
   the client carries, and commits the result back.

Key holders can collapse all three with
`registry_publish.sh path/to/pkg.mspkg --sign --key <file>`.

Validate locally before committing - no key needed:

```bash
bash mac/bin/registry_sign.sh
```

Holders of the signing key can also sign locally with
`bash mac/bin/registry_sign.sh --sign --key <file>`, but the workflow is the
normal path: `MS_SIGNING_KEY` lives in repository secrets.

### What the signature covers

The minified, key-sorted JSON of the document **without** the signature field,
signed with `MS_SIGNING_KEY` - the same RSA-2048 key Guardian verifies
`MANIFEST.json` against:

```bash
jq -c -S '{formatVersion, generated, entries}' registry/index.json
```

`jq -c -S` is required: the client rebuilds this exact byte sequence, and
`hs.json.encode` alone does not sort keys.

`generated` is stamped by the signer, not by hand. It is inside the signed
payload, so an empty or missing value is not merely untidy - `hs.json.encode`
omits an absent key where `jq -c -S` writes an explicit `null`, and the two
byte sequences will not match. The validator rejects a signed document whose
`generated` is empty for that reason.

## Where the index comes from at runtime

`ms_registry.lua` tries three sources in order, and **signature-checks all
three** - a local copy is not trusted for being local:

| Source | Path | Notes |
| --- | --- | --- |
| network | `raw.githubusercontent.com/.../registry/index.json` | 6-hour TTL |
| cache | `data/ms_registry_cache.json` | last good fetch |
| bundled | `data/registry_index.json` | ships in the release archive |

The bundled copy is what a fresh install with no network reads. It is the
signed index as of build time, so it goes stale rather than wrong.

An index whose signature does not verify is discarded whole - not served with
its trust downgraded. A forged document does not get to choose which of its own
claims are believed. The client then reports zero entries and answers
`"unsigned"` for every hash, which is the same behaviour as no index at all.
