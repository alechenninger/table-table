# table-table web

A client-only Jaspr app. `lib/app.dart` owns the small amount of UI state and calls
the shared `slack_table` package via a path dependency. The browser entry point
supplies clipboard access; the component tests supply an in-memory replacement.

Requires Dart 3.10+ and Node.js 20+. Install both sets of dependencies, then start
Jaspr and the CSS watcher together:

```sh
dart pub get
npm ci
npm run dev
```

```sh
dart analyze
dart test
npm run build
```

Deploy the contents of `build/jaspr/` to a static host over HTTPS. The app has no
server, storage, or third-party runtime requests.

daisyUI supplies the control styles and the Nord (light) / Dim (dark) themes,
following the system preference. `styles/app.css` configures daisyUI, page defaults, and native
popover anchoring. Layout and control sizing use Tailwind utilities in `lib/app.dart`. Tailwind scans `lib/` for complete class names; keep conditional
classes as full strings rather than constructing individual utility names from fragments.
Shared class lists may be constants, provided every utility name is written in full.

The responsive scale keeps table text and the format selector at `text-base`,
actions and supporting text at `text-sm`, and primary controls at least `min-h-11`
(44px at the default root size). The secondary actions use `min-h-9`
with `px-2 py-1` for a more compact footprint. Both use `btn-outline` with a subtle
`border-base-content/20`, and their outer edges align with the editor.
Pane padding grows from `p-4` to `sm:p-6`;
the copy toolbar stacks below `sm` instead of shrinking its labels. Buttons use
auto height so enlarged text can grow. Wide table content scrolls inside its
preview, while headings and surrounding controls can wrap. Keep these proportions
when adding controls and check both sides of the `sm` breakpoint plus 320px reflow.

Clear input becomes Undo clear until the user enters new text or loads an example.
Undo restores the original input, source format, and column choice while retaining
the current output destination. The undo history stays in memory and has no timer.

`npm run build:css` generates `web/styles.css`, which is ignored by Git. The dev
command watches CSS and Dart sources; the production build and root `--web`
check both rebuild CSS first. Use these commands rather than calling Jaspr
directly, which does not run the CSS build. Node is only a build dependency;
the deployed site serves a local stylesheet with no CSS framework runtime.

Keep generated `*.client.options.dart` files out of version control; Jaspr builds
them automatically. The CLI version is pinned by this package's lockfile, so no
global Jaspr installation is needed.
