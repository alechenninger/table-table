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
following the system preference. `styles/app.css` configures daisyUI and contains
the app layout. Tailwind scans `lib/` for complete class names; keep conditional
classes as full strings rather than constructing them from fragments.

`npm run build:css` generates `web/styles.css`, which is ignored by Git. The dev
command watches CSS and Dart sources; the production build and root `--web`
check both rebuild CSS first. Use these commands rather than calling Jaspr
directly, which does not run the CSS build. Node is only a build dependency;
the deployed site serves a local stylesheet with no CSS framework runtime.

Keep generated `*.client.options.dart` files out of version control; Jaspr builds
them automatically. The CLI version is pinned by this package's lockfile, so no
global Jaspr installation is needed.
