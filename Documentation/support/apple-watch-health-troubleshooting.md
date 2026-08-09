# Apple Watch & Health — Support Troubleshooting

Use this guide when users report missing sleep, steps, or recovery data. Copy aligns with in-app messaging in Look After.

## Mental model (explain this first)

Look After **never connects to the Apple Watch directly**. Data flows:

**Apple Watch → iPhone Health app → Look After**

If data appears in Health but not Look After, it is usually a permission or sync issue inside Look After — not a Watch pairing problem.

---

## Status kinds (in-app diagnosis)

| Status | User sees | Meaning | Primary fix |
|--------|-----------|---------|-------------|
| **Not set up** | Connect Apple Health | No Health access yet | Connect Apple Health in app |
| **Access blocked** | Look After can't read your Health data | iOS denied or restricted access | Health app → Sharing → Apps → Look After → enable Sleep, Steps, Heart Rate |
| **Tracking off** | Health tracking is turned off | App toggle disabled | Settings → Features → Health Tracking ON |
| **Waiting for data** | Connected, but no data yet | Authorized, no metrics in Health yet | Wear Watch overnight; confirm data in Health app; Sync now |
| **Partial data** | Some health data is missing | Some metrics imported, others not | Per missing metric (see below) |
| **Sync delayed** | Health data may be out of date | Last sync > 24h | Sync now |
| **All good** | Sleep and activity are up to date | — | None |

**Important:** iOS does not tell apps which Health categories were denied. Always say *"Check that Sleep, Steps, and Heart Rate are enabled"* — never claim a specific permission was denied unless verified in Health → Sharing → Apps.

---

## Copy-paste responses

### Not set up

> Look After reads sleep and activity from the Health app on your iPhone (including data from your Apple Watch). Tap **Connect Apple Health** on Today and allow Sleep, Steps, and Heart Rate when iOS asks.

### Access blocked

> Your iPhone is blocking Health access. Open the **Health app → Sharing → Apps → Look After** and turn on **Sleep**, **Steps**, and **Heart Rate**. Then return to Look After and tap **Sync now**.

### Tracking off

> Health tracking is turned off inside Look After. Open **Settings → Features**, turn **Health Tracking** on, then tap **Sync Apple Watch Data Now**.

### Waiting for data

> You're connected, but there's no sleep or activity in Health yet for us to import. Wear your Apple Watch overnight, open the Health app to confirm data is there, then tap **Sync now** in Look After.

### Partial data (steps work, sleep doesn't)

> Some data came through, but sleep isn't available yet. Enable **Sleep** for Look After in **Health → Sharing → Apps**, wear your Watch overnight with Sleep tracking on, and tap **Sync now**.

### Sync delayed

> Look After hasn't refreshed recently. Tap **Sync now**, keep Bluetooth on so your Watch can sync to your iPhone, and confirm newer data appears in the Health app first.

### All good

> Sleep and activity are up to date. Look After is reading your latest data from the Health app.

---

## Decision tree (support staff)

```
User reports missing data
├─ Health Tracking OFF in Look After?
│  └─ YES → Enable in Settings → Features → Sync
├─ Never connected / denied permission?
│  └─ Health → Sharing → Apps → Look After → enable categories
├─ Health app has NO data?
│  └─ Watch/iPhone tracking issue (not a Look After bug)
│     • Wear Watch overnight / walk for steps
│     • Confirm Sleep app or Watch Sleep is enabled
├─ Health app HAS data, Look After empty?
│  └─ Sync now + verify permissions
│     • Still empty after sync → escalate (possible bug)
└─ Data stale (>24h)?
   └─ Sync now + background refresh note (can take minutes after waking)
```

---

## Expected behavior

- **Watch → iPhone sync** can take minutes after waking; data may appear in Health before Look After shows it.
- **Background refresh** runs on a schedule (roughly hourly when conditions allow); foreground sync is immediate via **Sync now**.
- **Simulators** cannot read real Health/Watch data — test on a physical iPhone.
- **Energy/recovery without sleep** may show as *Estimated* until overnight sleep is available.

---

## Escalation criteria (likely bug)

Escalate to engineering when **all** are true:

1. User is signed in
2. Health Tracking is ON in Look After
3. Sleep, Steps, and Heart Rate enabled for Look After in Health → Sharing → Apps
4. Health app shows the missing metrics for the relevant date range
5. **Sync now** completed successfully (no error in verification)
6. Look After still shows dashes or wrong status after force-quit and reopen

Collect: iOS version, Watch model (if any), last sync time, screenshot of Health → Sharing → Apps → Look After, and verification report from Settings if available.

---

## Screenshot callouts

1. **Health app → Browse → Sleep** — confirm last night's sleep exists
2. **Health app → Sharing → Apps → Look After** — all relevant toggles ON
3. **Look After → Today** — health status banner headline and primary action
4. **Look After → Settings → Apple Watch & Health** — status row and last synced time

---

## Manual QA script

1. Fresh install → **Not set up** banner with Connect action
2. Deny Health permission → **Access blocked** + Open Health guidance
3. Grant permission, no Watch sleep → **Waiting for data**
4. Health has sleep, Look After empty → Sync + permission check
5. Toggle Health Tracking off → **Tracking off** message

---

## Related in-app entry points

- **Today (Briefing)** — status banner when metrics missing or status needs attention
- **Settings → Apple Watch & Health** — status row, Sync, Open Health, Help with Watch data
- **Health detail sheet** — Sync now, Open Health, verification checks
- **Help with Watch data** — troubleshooting accordion with live status
