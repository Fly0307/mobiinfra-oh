# AGENT.md

This project is a HarmonyOS NEXT ArkTS app. The entry page currently lives at:

- `entry/src/main/ets/pages/Index.ets`
- Shared header component: `entry/src/main/ets/components/AppHeader.ets`
- Main tab UI components:
  - `entry/src/main/ets/pages/home/HomePage.ets`
  - `entry/src/main/ets/pages/collection/CollectionPage.ets`
  - `entry/src/main/ets/pages/task/TaskPage.ets`

The app started as a local model inference demo. It is being redesigned into a "数据归家" app, but the existing local inference logic must be preserved unless the user explicitly asks to change it.

## Project Context

- DevEco Studio is installed at `D:\download\deveco\DevEco Studio`.
- `Index.ets` owns app-level state, bottom tabs, and the local inference/assistant logic.
- Home, collection, and task UI should stay in their own component files.
- Current added media assets:
  - `entry/src/main/resources/base/media/digital_avatar.png`
  - `entry/src/main/resources/base/media/rec_food.png`
  - `entry/src/main/resources/base/media/rec_sport.png`
  - `entry/src/main/resources/base/media/rec_travel.png`
- `.gitignore` includes `/.hvigor-user-home` for local hvigor cache experiments.

## Build And Sandbox Notes

Running DevEco hvigor from Codex may fail because the sandbox blocks writes to the Windows user directory and network access.

The normal DevEco preview command uses:

```powershell
& 'D:\download\deveco\DevEco Studio\tools\node\node.exe' `
  'D:\download\deveco\DevEco Studio\tools\hvigor\bin\hvigorw.js' `
  --mode module `
  -p module=entry@default `
  -p product=default `
  -p pageType=page `
  -p compileResInc=true `
  -p requiredDeviceType=phone `
  -p previewMode=true `
  -p buildRoot=.preview `
  PreviewBuild `
  --analyze=normal `
  --parallel `
  --incremental `
  --daemon
```

Observed failures:

- `EPERM: operation not permitted, create C:\Users\fenge\.hvigor\wrapper\tools\package.json failed`
- `npm ERR! FetchError ... https://repo.huaweicloud.com/repository/npm/pnpm ... connect EACCES`

If this happens, first try redirecting hvigor user home into the repo:

```powershell
$env:HVIGOR_USER_HOME=(Resolve-Path '.').Path + '\.hvigor-user-home'
& 'D:\download\deveco\DevEco Studio\tools\node\node.exe' 'D:\download\deveco\DevEco Studio\tools\hvigor\bin\hvigorw.js' --mode module -p module=entry@default -p product=default -p pageType=page -p compileResInc=true -p requiredDeviceType=phone -p previewMode=true -p buildRoot=.preview PreviewBuild --analyze=normal --parallel --incremental --daemon
```

This can still fail if the sandbox blocks network downloads. In that case, do not keep retrying blindly. Ask the user to run DevEco locally and paste the new ArkTS errors, or request escalation if allowed by the current environment policy.

## Git Notes

This repo can trigger dubious ownership warnings. Use:

```powershell
git -c safe.directory=D:/MobiAgent/mobiinfra-oh -C d:\MobiAgent\mobiinfra-oh status --short
```

Avoid `git reset --hard` or reverting user changes.

## ArkTS Pitfalls Seen In This App

- ArkTS does not support typed catch clauses. Use `catch (e) { let err = e as Error; ... }`, not `catch (e: Error)`.
- Avoid `any` and `unknown`; strict ArkTS reports `arkts-no-any-unknown`.
- Object literals often need explicit interfaces/classes.
- Function return types may need explicit annotations.
- Use `JSON as ArkJSON` from `@kit.ArkTS` where strict JSON typing is needed.
- Keep only one `build()` method in an `@Entry` component.
- Special Unicode symbols in UI can render as tofu boxes or strange glyphs in the Harmony previewer. Prefer stable text labels, simple drawn shapes, or resource icons.
- Avoid `Button('line1\nline2')` for complex button content. Use a clickable `Column`/`Row` with separate `Text` nodes instead.

## UI Layout Notes

The app is often previewed on 1080 x 2340 phone frames. Avoid hardcoded wide horizontal layouts.

For stable layouts:

- Use `layoutWeight(1)` for flexible text/content areas.
- Add `maxLines(1 or 2)` and `textOverflow({ overflow: TextOverflow.Ellipsis })` for titles.
- Keep bottom safe space below scroll content, because the tab bar can cover the last card/button.
- Use smaller text inside compact cards and tab bars.
- Avoid relying on special-symbol icons such as `⌂`, `✧`, `☑`, `▤`, `◷`, `→`, `●`, `›`.
- Bottom navigation should reflect `currentTab`; selected tab is blue and inactive tabs are gray.

## Local Inference Logic

When changing the "数据归家" UI, do not change the local inference behavior unless requested. Preserve these flows:

- `prepareCustomOpp`
- `mnnllm.loadModel`
- `mnnllm.generate`
- `mnnllm.chat`
- `mnnllm.reset`
- `LlmServer.start`
- model download/config/debug helper functions
- navigation to `pages/OpTest` and `pages/LogView`

UI can be restyled, but core calls and data paths should remain intact.
