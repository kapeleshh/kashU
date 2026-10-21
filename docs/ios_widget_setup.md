# iOS home-screen widget — Xcode setup

The Android home-screen widget is complete. The Flutter side already writes
shared data for iOS (`lib/services/widget_update_service.dart`: app group
`group.com.kashu.app.widget`, widget kind `PortfolioWidget`, keys
`portfolio_value` / `gain_loss` / `gain_loss_pct` / `is_positive`). This PR adds
the native WidgetKit sources; the one remaining step **must be done in Xcode on
a Mac** (adding an app-extension target can't be scripted safely). It could not
be built/verified in the dev environment used to write it.

Provided files:
- `ios/PortfolioWidget/PortfolioWidget.swift` — the WidgetKit widget (reads the
  app group, renders value + ▲/▼ gain/loss + pct + updated time; small & medium).
- `ios/PortfolioWidget/PortfolioWidgetBundle.swift` — the `@main` bundle.
- `ios/PortfolioWidget/Info.plist` — extension Info.plist (WidgetKit extension point).
- `ios/PortfolioWidget/PortfolioWidget.entitlements` — app-group entitlement for the extension.
- `ios/Runner/Runner.entitlements` — app-group entitlement for the main app.

## Steps (Xcode)

1. **Open** `ios/Runner.xcworkspace` in Xcode.
2. **Add the target:** File → New → Target → **Widget Extension**. Product name
   **`PortfolioWidget`**, **uncheck** "Include Live Activity" and "Include
   Configuration App Intent" (this widget uses a `StaticConfiguration`). Finish;
   when prompted, **activate** the scheme. Set the extension's **iOS Deployment
   Target to 14.0+** (WidgetKit requires it; the app itself stays at its current
   target).
3. **Use the provided sources:** Xcode generates a starter `PortfolioWidget.swift`,
   a bundle file, and `Info.plist` in a new group. Delete Xcode's generated
   `.swift` files and add the two provided ones (`PortfolioWidget.swift`,
   `PortfolioWidgetBundle.swift`) to the **PortfolioWidget** target, and replace
   the generated `Info.plist` with the provided one (or keep Xcode's — the key
   part is the `NSExtensionPointIdentifier`). Make sure exactly one file has
   `@main` (the bundle).
4. **App Group capability on BOTH targets:** select the project → **Runner**
   target → Signing & Capabilities → **+ Capability → App Groups** → add
   `group.com.kashu.app.widget`. Repeat for the **PortfolioWidget** target.
   Point each target's "Code Signing Entitlements" build setting at the provided
   entitlements files (`Runner/Runner.entitlements` and
   `PortfolioWidget/PortfolioWidget.entitlements`) if Xcode created its own.
5. **Signing:** set the same development team on the PortfolioWidget target as
   Runner (automatic signing).
6. **Build & run** on a device or simulator, then long-press the home screen →
   add the **KashU Portfolio** widget. Open the app and pull-to-refresh once so
   `WidgetUpdateService` populates the shared data; the widget fills in on its
   next timeline reload (the app calls `HomeWidget.updateWidget` after each
   refresh).

## Notes
- The widget reads the raw keys written by the `home_widget` plugin under the
  app-group `UserDefaults`. If a future `home_widget` upgrade prefixes keys,
  update the `forKey:` strings in `PortfolioWidget.swift` to match.
- `pubspec.yaml` already depends on `home_widget`; no Dart changes are needed.
- Values in the widget follow the app's base currency (the shared strings are
  pre-formatted by `WidgetUpdateService`).
