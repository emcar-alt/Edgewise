# PrivateAPI

`edgewisectl` calls into `/System/Library/PrivateFrameworks/UniversalControl.framework`, the
framework the Universal Control agent itself is built on. Apple ships no headers or Swift
interface for it, so this folder provides the two pieces Swift needs:

| File | Purpose |
| --- | --- |
| `UniversalControl/UniversalControl.swift` | Declarations matching the framework's public Swift API. Compiled with `-emit-module -enable-library-evolution` only for type checking; it is never linked. |
| `UniversalControl.tbd` | A text stub listing the exact symbols `edgewisectl` uses, so the linker can resolve them. At runtime dyld binds them to the real framework in the shared cache. |

## Where the API came from

- **Symbol list.** System frameworks live in the dyld shared cache, so there's no file to run `nm` on. `scripts/exports.c` loads the framework and walks its export trie in memory. The Swift API (`UniversalControlConfiguration.init(data:)`, `.links()`, `.removingLinks(where:)`, `.addingLinks(_:)`, `.encoded()`, `.digest`, `UniversalControlLink.init(endpoint1:endpoint2:)` and so on) comes from demangling those exports.
- **Value layouts.** Swift only lets a client hold a type's fields directly if the type is `@frozen`; everything else is passed indirectly. Disassembling the agent (`/System/Library/CoreServices/UniversalControl.app`) at its call sites shows which is which:
  - `UniversalControlEdge` is returned in `w0` and `init(intValue:)` returns `4` for `nil`: a frozen enum with four cases.
  - `UniversalControlDeviceID` comes back in `x0`–`x1` (16 bytes) and `UniversalControlDisplayID` in `x0`–`x3` (32 bytes): frozen structs of `UniversalControlUUID` (a `uuid_t`).
  - `UniversalControlAnchor`, `UniversalControlLink`, `Link.Endpoint` and `UniversalControlConfiguration` are returned through `x8` and passed as `self` in `x20`: resilient, so their layout doesn't matter to us.
- **Verification.** Decoding the stored configuration and re-encoding it reproduces the original bytes exactly, and `digest` equals the stored `ConfigurationID`. `edgewisectl` repeats a round-trip check before every write.

## The stored format, for reference

`~/Library/Preferences/ByHost/com.apple.universalcontrol.<host UUID>.plist` holds:

- `Configuration`: a binary plist `{ vers: 3, head: <digest>, heap: [...], refs: {} }`. Each heap node is `[digest, timestamp(ms since 2001), parentCount, parents..., linkCount, links...]`, and each link is `[timestamp, edge, deviceA, displayA, deviceB, displayB, offsetA, offsetB]` with edges `0…3` and offsets scaled to `0…65535`.
- `ConfigurationID`: the head digest.

The agent (`com.apple.ensemble`) observes these keys and re-solves the layout as soon as they change, then syncs the new head to the iPad.

## When macOS changes

If a release renames or removes something, dyld refuses to launch `edgewisectl` and the app shows a notice. To update:

1. Run `scripts/exports.c` (via `scripts/gen-tbd.sh`) to see the current exports.
2. Adjust `UniversalControl.swift`, rebuild, and run `scripts/gen-tbd.sh` with the helper's object files.
3. Check `edgewisectl dump` round-trips and `edgewisectl set … --dry-run` produces the expected link.
