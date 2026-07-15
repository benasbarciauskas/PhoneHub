## Summary

<!-- One or two sentences: what does this PR do, and why? -->

## What changed

-

## Testing done

<!-- What you ran/checked. Include device platform / OS version if relevant. -->

- [ ] `swift build --disable-sandbox` passes
- [ ] `swift test --disable-sandbox` passes
- [ ] Manually verified against a real device (iOS / Android) where applicable:

## Checklist

- [ ] Build passes (`swift build`)
- [ ] Tests pass (`swift test`)
- [ ] No secrets committed (`.env`, tokens, keys, `*.session.json`, cookies)
- [ ] Input from boundaries (UDIDs / serials, shell args to `idevice*`/`adb`/`scrcpy`) is validated — no shell injection
- [ ] Changes are focused; unrelated files were not touched
- [ ] Branch follows `<type>/<slug>` (`feat|fix|chore|refactor|docs`)
