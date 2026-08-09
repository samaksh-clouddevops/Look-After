# Capture Routing — Support Guide

Look After capture auto-routes voice/text to the right destination. This mirrors in-app behavior after the capture revamp.

## How it works

1. User speaks or types in the **Capture composer** (bottom nav, Briefing header, Brain menu, or Inbox).
2. Optional **type chips** hint intent (Task, Note, Event, Mood, Insight) — **Auto** lets AI decide.
3. **CaptureRouter** classifies and routes:
   - **Task** → Today task list
   - **Event** → Scheduled task on timeline (fixed time)
   - **Note / Insight** → Reflection journal
   - **Mood** → Energy/mood log (Brain health context)
   - **Low confidence** → Inbox review queue

4. User sees an **undo toast** (5 seconds) for task/event creation.

## User-facing messages

| Outcome | Toast example |
|---------|----------------|
| Task | Added Buy milk to Today |
| Event | Scheduled Dentist for Tue 3:00 PM |
| Journal | Saved to journal · … |
| Mood | Logged mood · Okay |
| Needs review | Saved to Inbox for review · … |

## Inbox role

Inbox is now a **review queue**, not the primary capture path.

- **Needs review** — routing was uncertain; user taps "Fix routing"
- **Recently routed** — audit trail of auto-processed captures

Badge counts: unprocessed + needs review only.

## Troubleshooting

### Capture saved but nothing on Today

- Check toast — may have routed to journal or mood instead of task
- Open Inbox — item may be in "Needs review"
- Tap **Fix routing** to re-run AI processing

### Voice not working

- Settings → Look After → Microphone / Speech Recognition
- Composer shows **Open Settings** when permission denied

### Planning assistant "remember to…"

Planning mutations with `captureNote` now route through CaptureRouter as tasks.

## Expected behavior

- Capture composer shows text field and mic **immediately** (no type menu first)
- Save dismisses composer and shows toast within ~2 seconds
- Offline queue: planned; currently requires network for AI routing

## Escalation

Escalate if: capture text saved, toast says success, but no task/journal/inbox entry after force-quit and reopen (signed in, online).

Collect: capture text, toast message, Inbox screenshot, iOS version.
