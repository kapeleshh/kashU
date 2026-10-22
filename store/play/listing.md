# Google Play listing — KashU

Copy for the Play Console "Main store listing" and "App content" sections.
Character limits are Play's own; counts below are current.

---

## App name  (max 30)

```
KashU — Portfolio Tracker
```
*(25 characters)*

## Short description  (max 80)

```
Track stocks, mutual funds, gold, crypto and deposits — privately, offline.
```
*(74 characters)*

## Full description  (max 4000)

```
KashU keeps your whole investment portfolio in one place — and keeps it on your phone.

No account. No sign-up. No ads. Your holdings never leave your device.

WHAT YOU CAN TRACK
• Stocks and ETFs — search by company name, with NSE / BSE / NASDAQ / NYSE filters
• Mutual funds — 37,500+ Indian schemes, with live NAV
• Gold and silver — live COMEX prices converted to ₹/gram, including Indian import duty and GST
• Cryptocurrency — live prices, searchable by name or symbol
• Fixed and recurring deposits — enter the principal and rate, or just the maturity amount and let KashU work backwards
• Real estate, cash and anything else — tracked manually

LIVE PRICES, ONE TAP AWAY
Tap refresh or pull down on the dashboard to update every price from free public market data sources. When a source is unavailable KashU falls back to a second provider, then to the last known price, so your portfolio still adds up offline.

SEE HOW YOU ARE ACTUALLY DOING
• Total value, total invested, and gain/loss at a glance
• Asset allocation chart and top gainers/losers
• 90 days of history, with per-asset sparklines and day-over-day change
• Home screen widget showing your portfolio value

REBALANCING
Set a target allocation for each asset type, see how far you have drifted, and get the amounts that bring you back in line.

TAX EXPORT
Export your holdings and transactions as CSV, or generate a capital-gains PDF split into short-term and long-term — ready to hand to your accountant.

BUILT FOR PRIVACY
• Everything is stored locally, in an AES-256 encrypted database
• The encryption key lives in the Android Keystore
• No analytics, no tracking, no advertising identifiers
• Crash reporting is opt-in and off by default
• Optional app lock using your fingerprint or device PIN

Multi-currency support with a configurable base currency, light and dark themes that follow your device, and full JSON export and import so your data is always yours to take with you.

KashU does not provide investment advice and does not execute trades. It is a tracker — prices come from public market data sources and may be delayed.
```

---

## App content declarations

| Field | Answer |
|---|---|
| Privacy policy URL | `https://kash-u.vercel.app/privacy.html` |
| Contact email (public) | `onelunchdev@gmail.com` (also in the privacy policy and Settings › About) |
| Ads | **No ads** |
| Content rating | Everyone (finance/utility; no user content, no ads) |
| Target audience | 18+ (financial tool; not directed at children) |
| Data safety — collected | **None** |
| Data safety — shared | **None** |
| Data safety — encrypted in transit | Yes (all requests are HTTPS) |
| Data safety — deletion | N/A — nothing is collected; data is local and removed with the app |
| Government app | No |
| Financial features | **No** — KashU tracks a portfolio; it does not execute trades, lend, or offer financial services |

### Note on the data-safety form

Answer "no data collected" **only if you ship without a Sentry DSN**. Crash reporting is compiled
out unless `--dart-define=SENTRY_DSN=...` is passed at build time *and* the user opts in
(`lib/main.dart:211`). If you ever ship with a DSN baked in, you must declare
**Crash logs (Diagnostics)** — optional, not shared, collected only with consent.

---

## Graphics checklist

| Asset | Requirement | Status |
|---|---|---|
| App icon | 512×512 PNG, 32-bit | ✅ `store/play/icon-512.png` |
| Feature graphic | 1024×500 PNG/JPG | ✅ `store/play/feature-graphic-1024x500.png` |
| Phone screenshots | 2–8, min 320px, 16:9 or 9:16 | ❌ **still needed** |
| 7" / 10" tablet screenshots | Optional | ❌ not planned for v1 |

Regenerate the two graphics (and every app icon) with `python3 tool/generate_brand_assets.py`.

**Screenshots still to capture** — the four screens that show the app at its best:
dashboard with holdings, asset detail with sparkline, rebalancing, tax export.
Take them on a device with realistic (non-empty) data.
