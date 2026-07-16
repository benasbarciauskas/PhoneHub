# Interactive Action Timeline Builder Design

## Goal

Replace the one-off command box with a persisted, chat-driven automation builder
that captures one phone action per message, supports manual tap placement, and
resolves reusable text sources at run time without breaking existing automation
JSON.

## Architecture

The builder is a focused view embedded in `PresetsPanel`. It owns transient chat
message statuses while a `BuilderDraftStore` owns the durable draft. A draft is
initially platform-neutral and becomes pinned to the focused device platform when
its first step is added. Changing to another platform preserves the draft but
disables additions and runs until the original platform is focused or the draft is
cleared.

`AutomationEngine.runBuilderAction` uses the existing agent plumbing with a
builder-specific system preamble. The agent may inspect the screen, must perform
exactly one mutating phone action, and must then stop. Captured calls are converted
with `AutomationCapture`; the builder accepts exactly one resulting action step.
Zero or multiple captured actions are reported as a failed builder message and are
not appended.

The timeline uses a SwiftUI `List` with `.onMove` and `.onDelete`. Rows share the
existing automation step presentation helpers and expose focused editors for wait,
literal/source-backed text, AI steps, and tap targets. Toolbar actions append new
steps; each row also supports inserting these steps immediately after itself.

## Persistence and Compatibility

`BuilderDraftStore` persists one `BuilderDraft` in Application Support using the
existing atomic JSON-write pattern. The draft contains platform, steps, and a
parallel `[UUID: TextSourceRef]` binding map.

`TextSourceStore` persists `[TextSource]` separately. `TextSource` contains an ID,
name, sanitized items, cursor, and `.static` or `.cycle` mode.

`Automation` gains a parallel `textSourceBindings` map. Its custom decoder treats
the field as empty when absent, so all existing automation files remain decodable.
`AutomationStep.typeText` remains unchanged. Deleting or replacing a step prunes
its draft binding. Missing sources fail a run before any phone action occurs.

## Text Source Parsing

`TextSourceParser` is pure Core logic. It rejects input larger than 1 MB or invalid
UTF-8 before parsing and caps results at 10,000 non-empty items. Control characters
other than newline and tab are removed.

- TXT recognizes a document when every non-empty line is numbered or bulleted. If
  not, two or more blank-line-separated blocks become items. Otherwise the entire
  document is one item.
- JSON accepts only a top-level string array or `{ "items": [String] }`. A
  string-aware nesting scan rejects excessive depth before `JSONSerialization`.
- XML accepts only `<items>` containing direct `<item>` children. DTD/entity
  declarations are rejected, external entity resolution stays disabled, and any
  parser or structural error rejects the file.

Imported multi-item sources default to cycle mode; single-item sources default to
static mode. Users can change the mode, reset the cursor, rename, or delete sources.

## Run Resolution

At run start, all source-bound type-text steps are resolved before the MCP client
starts. One current item is selected per source, so multiple steps bound to the same
source receive the same text during one run. Static sources never advance. Cycle
sources advance once only after the entire run finishes successfully; stopping,
failure, missing-device pauses, and recalibration pauses do not advance cursors.
Advancing from the last item to the first appends a wrapped message to the run log.

Community sharing resolves bound steps to their current literal text without
advancing any cursor because the community format has no source concept.

## Manual Tap Picker and Coordinate Mapping

The picker starts a direct MCP client for the focused platform, fetches a fresh
screenshot, and also fetches mirroir `status` on iOS. Android screenshot pixels are
the same device-pixel coordinates consumed by ADB tap. Mirroir screenshots use
display backing pixels, while `tap` and `describe_screen` use top-left mirroring
window points; the authoritative point-space size is parsed from mirroir's current
`status` window dimensions.

`mapClickToDevicePoint(clickInView:viewSize:imagePixelSize:deviceSpaceSize:)` is a
pure function. It computes the screenshot's aspect-fit rectangle, removes
letterboxing, clamps clicks to image bounds, converts to image pixels, then scales
to the MCP device space. Unit tests cover vertical and horizontal letterboxing,
edges, clamping, differing Retina scale factors, and non-uniform image/device
dimensions.

The sheet dims the screenshot, records a top-left local click, shows a crosshair,
and offers Confirm, Retake, and Cancel. Confirm adds or updates the selected tap,
double-tap, or long-press without executing it and preserves the step ID and long
press duration. An optional label remains available for semantic recalibration and
community sharing.

## Errors and Validation

All device operations validate Android serials and direct-client results. Screenshot
or status failures remain in the picker with a retry path. File import errors are
clear and format-specific. Wait durations and long-press durations are clamped to
non-negative safe values. Empty AI requests, empty literal type-text steps, and
empty timelines cannot run or save.

## Testing and Delivery

Pure logic is developed red-green with XCTest: coordinate mapping, status-size
parsing, capture cardinality, text parsing/security cases, text resolution and
cursor advancement, draft persistence, and backward-compatible automation decode.
After UI integration, the full Swift test suite and required Swift build command
must pass. The final diff receives an adversarial self-review with a merge verdict,
then commit authorship is verified.
