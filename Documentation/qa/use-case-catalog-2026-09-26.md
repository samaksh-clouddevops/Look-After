# Look After — use cases and user scenarios

**Date:** 26 Sep 2026  
**Purpose:** Step 1 of the deep bug pass. Every later simulation checks one row: given this person and moment, did the app do what this catalog says it should?  
**Sources:** `ATTENTION_OS_SPEC.md` (product contract), `Documentation/qa/02`–`06` (feature areas, screens, flows, edges), README feature list, and the day-plate contract on `feature/virtual-clock-redesign-and-widget-fixes` (`2c7c154`).

Shipped app name is **Look After**. Spec name FlowOS maps as: Flow Director → Executive Brain, Flow Canvas → Today / Briefing, Flow → focus session, Anchor Mode → Emergency Mode, Capture → composer, Stack → task list.

---

## How a scenario is judged

| Column | Meaning |
|--------|---------|
| **Given** | Starting world (account, day, permissions, clock) |
| **When** | The one action or system event |
| **Then** | Observable result. Anything else is a bug. |

Pass only if the result is true on the surface the user sees **and** after kill/relaunch when the scenario says the data must survive.

---

## Personas

| ID | Who | What they need the app to get right |
|----|-----|--------------------------------------|
| P1 | New person, fresh install | Sign in, onboarding, land on a calm today with a next action |
| P2 | Returning person with a routine | Meals, gym, meds, and blocks appear every day without retyping |
| P3 | Person running a multi-day goal | Slices stay on the right days; the goal does not vanish or duplicate |
| P4 | Person who missed the window | See it, reschedule or drop it from today; no shame copy |
| P5 | Person who finished the last few things | Done items stay in the schedule window; hero moves on |
| P6 | Overwhelmed person | Emergency shrinks the day to a few large choices |
| P7 | Health-aware person | Sleep/HRV change capacity; cycle stays medically conservative |
| P8 | Glance person | Widget and Live Activity match the in-app now task |
| P9 | Second device / sign-out person | Same account restores; a different account does not see the first person's tasks |

---

## Product promises (always in force)

1. Opening the app shows **one next action**, already chosen. The user confirms, starts, defers, or captures. They do not rebuild the day from a blank list.
2. **Energy and calendar beat a raw clock.** A free hour during a calendar block is not a free hour.
3. **No guilt language.** No “behind”, “failed”, or “you missed X”. A late item is an offer to move or dismiss.
4. **Done is celebrated, then replaced.** Completing the hero changes the hero. Completing an item does not erase it from the immediate schedule window.
5. **Every task source lands on the same plate.** Ad-hoc, routine blocks, daily seed, life-model commitments, recurrence, multi-day slices, and Apple calendar events are all inputs to Today, All tasks, the timeline, the future-day strip, and widgets.
6. **A day draft exists for any strip day**, not only today: routines, multi-day slices, tasks created for that day, and Apple events.
7. **Local actions work offline** and reconcile later without duplicate rows.
8. **Factory reset and sign-out leave no leftover personal rows** (tasks, parked queue, completed history, in-memory pools).
9. Max **two** proactive notifications a day. Rest is allowed.

---

## UC-01 First open

**Story.** As a new person, I install the app, sign in, and reach a named briefing without configuring a system.

| ID | Given | When | Then |
|----|-------|------|------|
| UC-01-A | Fresh install, online | Tap the icon | Auth screen. No briefing, no previous user's name. |
| UC-01-B | Auth screen, online | Sign in with Apple or Google | Account is accepted. Onboarding starts. |
| UC-01-C | Auth screen, airplane mode | Tap sign in | Error with retry. No half-created local profile. |
| UC-01-D | Auth fails (Firebase) | Tap sign in | Retry message. Stay on auth. |
| UC-01-E | Onboarding, step N | Force quit and relaunch | Same step, same answers so far. |
| UC-01-F | Onboarding | Skip Health | Continue. Capacity later uses a default band and a connect prompt. |
| UC-01-G | Onboarding, not tracking cycle | Skip or ineligible cycle step | Cycle stays hidden. |
| UC-01-H | Onboarding organize step, AI unavailable | Reach that step | Can skip. Onboarding still completes. |
| UC-01-I | Last onboarding step done | Finish | Briefing visible, name shown, routine seed present, `hasCompletedOnboarding` true. |
| UC-01-J | Onboarding complete | Relaunch | Auth and onboarding stay gone. Today opens. |

---

## UC-02 Start the day

**Story.** As someone opening the app in the morning, I see who I am, what energy I have, and one thing to start.

| ID | Given | When | Then |
|----|-------|------|------|
| UC-02-A | Onboarded, morning, tasks exist | Open Today | Greeting uses the profile name. One primary action. |
| UC-02-B | Brain has chosen a hero | Look at the first fold | Hero title is an incomplete, eligible task. Not a completed row. Not a template. |
| UC-02-C | User taps Start my day / hero | Start | Focus or the task session begins for that hero id. |
| UC-02-D | Hero completed | Complete it | Within a short refresh, hero id changes. The finished task is not offered again as now. |
| UC-02-E | User defers the hero | Defer | Hero changes. Deferred task is not immediately the hero again. |
| UC-02-F | Zero eligible tasks | Open Today | Calm empty state that offers capture. No fake task. |
| UC-02-G | Background 30s after complete | Return | Hero stays on the new task. |
| UC-02-H | Orchestration fails | Open or refresh | Last known hero stays, with a retry. No spinner forever. |
| UC-02-I | Classic mode, then AI Executive | Switch both ways | Same task ids, same hero intent, same name. |

---

## UC-03 Schedule window (today)

**Story.** As someone looking at today's plan, I see a short window around now: what I just did, what is now, and what is next — including finished items.

| ID | Given | When | Then |
|----|-------|------|------|
| UC-03-A | Several timed items today, one is current | Open Schedule preview | Window is **2 past + current + 2 next** (5 when that many exist). |
| UC-03-B | The two past items are completed | Open preview | Those completed rows are still in the window. |
| UC-03-C | Only one past item exists | Open preview | Window shrinks. It does not invent rows. |
| UC-03-D | Nothing is current; next incomplete is later | Open preview | Window centers on that next incomplete item. |
| UC-03-E | Full timeline opened | Scroll the rail | Same items as the plate for today, including completed today. Preview is a window of that rail, not a different list. |
| UC-03-F | Mark an in-window task done | Complete it | It remains in the preview as done. The current marker moves. |
| UC-03-G | Item is more than 2 hours past its window end, still incomplete, not meds or a bill | Look at Today | A card offers **reschedule** or **dismiss from today**. Copy does not shame. |
| UC-03-H | User reschedules the overdue item | Choose a new time | It leaves the overdue card and appears at the new time. |
| UC-03-I | User dismisses the overdue item from today | Dismiss | It leaves today's rail and is scheduled for tomorrow. It is not deleted. |
| UC-03-J | Overdue item is medication or a bill | Open Today | No generic “obsolete window” card for that item. |
| UC-03-K | Completed item is past the 2h grace | Open Today | It is not offered as something to reschedule. |

---

## UC-04 One plate for every source

**Story.** As someone with routines, a multi-day goal, a task I typed today, and a calendar, I see all of them in the same places.

Sources that must agree: ad-hoc tasks, recurrence occurrences, routine blocks, daily-routine seed, life-model commitments, multi-day roots and slices, Apple calendar events.

Surfaces that must read that plate: Schedule preview, full timeline, All / Upcoming / Active / Scheduled, future-day strip, widgets, execution environment.

| ID | Given | When | Then |
|----|-------|------|------|
| UC-04-A | Routine block “Gym” on today’s weekday | Load tasks | A gym row exists on today. It is not waiting for a second refresh. |
| UC-04-B | Life model already compiled **or** routine blocks exist | Cold load | Daily-routine seeder does not add a second Gym/Dinner/Lunch. |
| UC-04-C | Dinner from the life model and a recurring “Dinner” | Load today | One dinner series. Completing one does not fulfill the other by title alone. |
| UC-04-D | Multi-day goal with slices for today | Open timeline and All | Today’s slice is visible and active. It is not marked superseded because it has a parent id. |
| UC-04-E | Slices for Mon–Fri of one goal | Open each day | Each slice has its own identity. Completing Tuesday does not complete Wednesday. |
| UC-04-F | Apple event today, calendar allowed | Open timeline and a future strip day that has an event | Event appears on that day next to tasks. It is not turned into a duplicate task. |
| UC-04-G | Calendar denied | Open timeline | Tasks still show. No crash, no blank day. |
| UC-04-H | Task created for tomorrow only | Open tomorrow on the strip | That task is in tomorrow’s draft with routines and multi-day slices due that day. |
| UC-04-I | All-tasks filter | Open All | Active tasks from the full plate, not only today’s snapshot. Templates are hidden. |
| UC-04-J | Upcoming / Active / Scheduled filters | Switch filters | Each filter is the full plate with that filter, not a second hidden list. |
| UC-04-K | Today’s rail has zero scheduled tasks and a parked queue exists | Load today | Parked tasks restore onto today. |
| UC-04-L | Today’s rail already has scheduled tasks | Load today | Parked queue stays parked. |
| UC-04-M | Widget and Live Activity after a task change | Glance off-app | They show the same now task the plate would. |

---

## UC-05 Recurrence and clocks

**Story.** As someone with weekly and daily tasks, the next occurrence lands on the right day and a time-only clock does not jump days.

| ID | Given | When | Then |
|----|-------|------|------|
| UC-05-A | Weekly task completed today | Next load | Next due is +7 days. No second copy today. |
| UC-05-B | Daily task, time stored only as a clock | Open today and tomorrow | It stays on its clock day. Tomorrow does not steal it. |
| UC-05-C | One-off missed yesterday, still active | Open today | It may carry forward as overdue. A finished one does not. |
| UC-05-D | Recurrence template | Open All or timeline | Template row is hidden. Occurrences show. |
| UC-05-E | Timezone change overnight | Next morning open | Occurrences stay on the intended civil day. |
| UC-05-F | Two producers, same title, different series | Complete one | The other series remains. |

---

## UC-06 Capture

**Story.** As someone with a thought, I say or type it once and it lands in the right place, with undo.

| ID | Given | When | Then |
|----|-------|------|------|
| UC-06-A | Any main tab | Tap Capture | Composer opens. Save stays disabled until there is text. |
| UC-06-B | Typed “call dentist tomorrow 3pm” | Save | Routed to a task (or event if that is the classification) on the right day. Toast offers Undo and View. |
| UC-06-C | Mic allowed | Dictate and save | Same routing as text. |
| UC-06-D | Mic or speech denied | Open composer | Typing still works. A path to Settings is shown for voice. |
| UC-06-E | Dismiss composer without save | Close | Nothing is created. |
| UC-06-F | Offline | Save | Queued locally. Routes when the network returns. No duplicate after reconnect. |
| UC-06-G | Phone call during dictation | Call connects | Recording stops cleanly. Partial text is not silently submitted. |
| UC-06-H | Low-confidence route | Save | Lands in Inbox review instead of the wrong surface. |
| UC-06-I | Undo toast | Tap Undo | The created task or event is removed. |

Entry points that must all open this composer: bottom nav, briefing header, Brain, empty timeline, after focus, Inbox quick capture.

---

## UC-07 Plan with me

**Story.** As someone whose afternoon fell apart, I ask for a new plan and nothing moves until I confirm.

| ID | Given | When | Then |
|----|-------|------|------|
| UC-07-A | Several flexible tasks today, AI available | Ask to reorganize the afternoon | Conversation, then a preview of moves. |
| UC-07-B | Preview visible | Confirm | Tasks move. Timeline matches the preview. No overlapping slots. Life commitments stay put. |
| UC-07-C | Preview visible | Dismiss | Zero mutations. |
| UC-07-D | Network dies mid-reply | Wait | No partial apply. Retry is offered. |
| UC-07-E | Model returns invalid structure | Reply arrives | Error plus a non-AI fallback. Existing times unchanged. |
| UC-07-F | Offline before send | Ask | Offline message. No pretend plan. |
| UC-07-G | “Spread this over 5 days” | Confirm preview | One parent, five slices, no duplicate parents. |

---

## UC-08 Decide, focus, return

**Story.** As someone stuck, I let the app pick, do one block of work, get interrupted, and come back without losing the block.

| ID | Given | When | Then |
|----|-------|------|------|
| UC-08-A | Several pending tasks | Decide for me | Pick is one of the pending tasks. Copy does not shame. Completed tasks are not candidates. |
| UC-08-B | A task chosen | Start focus | Timer runs. Live Activity appears if the system allows it. |
| UC-08-C | Live Activities off | Start focus | In-app timer still runs. |
| UC-08-D | Call or app switch during focus | Return | Offer to continue the same session. No streak penalty. |
| UC-08-E | Force quit during focus | Relaunch | Session is recoverable or cleanly ended. Timer does not show a nonsense value. |
| UC-08-F | End focus | End | Live Activity goes away. Widget updates. Optional note can be captured. |
| UC-08-G | Focus ended on a completed task | Return to Today | Hero is the next task, not the one just finished. |

---

## UC-09 Overwhelm

**Story.** As someone flooded, I enter a small mode and leave it back on the normal day.

| ID | Given | When | Then |
|----|-------|------|------|
| UC-09-A | Any day with many tasks | Enter emergency | Full-screen mode. Bottom nav hidden. At most a few large choices. |
| UC-09-B | In emergency | Start a reset or a focus | That path works and returns to emergency or to the day, not a dead end. |
| UC-09-C | In emergency | Exit | Briefing returns. Nav returns. Emergency flag is off. |
| UC-09-D | Force quit inside emergency | Relaunch | Not trapped. Clear way back to Today. |

---

## UC-10 Tasks as a list

**Story.** As someone managing the backlog, filters, import, and completion history match the plate and do not resurrect old life.

| ID | Given | When | Then |
|----|-------|------|------|
| UC-10-A | Mixed statuses | Open Completed | Last 7 days only. Pre-reset history is absent after a factory reset. |
| UC-10-B | Same active title from two bugs | Open Completed and All | One row per real series. Dinner does not appear twice. |
| UC-10-C | Pasted list of N tasks | Import | N tasks created, no extras. |
| UC-10-D | Complete with undo | Undo | Task returns to active and to the plate. |
| UC-10-E | Edit time of a scheduled task | Save | Timeline, preview, and list agree on the new time. |
| UC-10-F | Delete a task | Delete | Gone from list, timeline, widget, and future days. |
| UC-10-G |  Act on a template | Try to complete the template row | User completes occurrences, not the hidden template. |

---

## UC-11 Health and cycle

**Story.** As someone who shares sleep or a cycle, the app uses it gently and never invents a medical claim.

| ID | Given | When | Then |
|----|-------|------|------|
| UC-11-A | Health not connected | Connect from onboarding or Settings | System sheet, then sync phases, then a capacity band. |
| UC-11-B | Health denied | Deny | Briefing continues. Connect prompt remains. |
| UC-11-C | One night of sleep | Sync | No “peak” band. Confidence stays low. |
| UC-11-D | Health revoked later | Next open | Capacity degrades. Reconnect is offered. |
| UC-11-E | Cycle enabled, anchor 14 days ago, 28-day cycle | Open cycle | Day index and phase match that anchor. |
| UC-11-F | Flow log with a gap of 21+ days | Log | Anchor moves to the log date. Day becomes 1. |
| UC-11-G | Flow log mid-cycle, short gap | Log | Anchor does not reset. |
| UC-11-H | Gender set to one that does not track cycle | Change in Settings | Cycle module hides. Old logs are not shown as current guidance. |
| UC-11-I | Luteal phase | Read briefing insight | Language matches luteal. No diagnosis. |

---

## UC-12 Brain, coach, inbox

**Story.** As someone asking for help, answers use my real tasks and profile, and uncertain captures wait in the inbox.

| ID | Given | When | Then |
|----|-------|------|------|
| UC-12-A | Pending tasks | Open Brain and ask it to decide | Recommendation is grounded in those tasks and current energy. |
| UC-12-B | Coach thread | Send a message | Reply tone matches settings. It can name real profile context. It does not invent completed work. |
| UC-12-C | No model key | Open planning or coach | Locked state explains how to add a key. Rest of the app works. |
| UC-12-D | Key added | Return to planning | Planning and coach unlock without reinstall. |
| UC-12-E | Inbox item routed wrong | Fix from the review card | Item moves. It does not also remain as a duplicate task. |
| UC-12-F | Background analytics refresh | Next briefing | Pattern cards update from the new cache. |

---

## UC-13 Account, reset, and a second person

**Story.** As the owner of this phone, my data follows my account and disappears when I reset or when someone else signs in.

| ID | Given | When | Then |
|----|-------|------|------|
| UC-13-A | Data on device | Settings → Factory reset → confirm | Tasks, parked queue, in-memory pools, onboarding flag, and model key are cleared. Onboarding shows. |
| UC-13-B | Kill during reset | Relaunch | No half-wiped store. Either reset finished or it is safe to run again. |
| UC-13-C | Reset finished, onboarding done | Open Completed and Today | No pre-reset dinner, lunch, or completed rows. New seed only. |
| UC-13-D | Signed in with data | Sign out | Local personal rows cleared. Auth screen. |
| UC-13-E | Same account signs back in | Sign in | Cloud tasks return. No duplicates of rows that were already local. |
| UC-13-F | Different account signs in | Sign in | None of the previous account’s tasks, name, or parked queue. |
| UC-13-G | Offline edits, then reconnect | Sync | Field merge or latest-wins per task. Same id is not two rows. |

---

## UC-14 Calendar write and modules

**Story.** As someone who wants the phone calendar to match the plan, writes happen only with permission, and life modules do not corrupt tasks.

| ID | Given | When | Then |
|----|-------|------|------|
| UC-14-A | Calendar write allowed | Schedule a task that should mirror | One EventKit event matches that task time. |
| UC-14-B | Read allowed, write denied | Schedule a task | In-app time updates. No event is created. No error loop. |
| UC-14-C | Shopping, meds, bills, journal modules | Add an item in that module | It stays in that module. It appears on the day plate only when the product treats it as a scheduled task. |
| UC-14-D | End-of-day journal | Save a note, optional speech | Entry saved. Optional summary does not rewrite tasks. |

---

## UC-15 Interruptions that apply to every P0 flow

Use on UC-01 through UC-09 and on planning.

| ID | When | Then |
|----|------|------|
| UC-15-A | Phone call mid-flow | No crash. Resume or a clean cancel. |
| UC-15-B | Home, wait 30s, return | State kept, or an explicit recovery card. |
| UC-15-C | Force quit and relaunch | No corrupt rows. A clear way back into the same job. |
| UC-15-D | Permission revoked mid-flow | Feature degrades with an explanation. |
| UC-15-E | Network drop during a model call | No partial writes. Retry offered. |

---

## Scenario walk order for the simulation

Run in this order so later steps see the data earlier steps created.

1. UC-01 fresh account.  
2. UC-02 first hero and complete.  
3. UC-04 sources: routine, second meal title, multi-day goal, calendar event, tomorrow task.  
4. UC-03 window, then complete inside the window, then age an item past two hours and reschedule, then dismiss another.  
5. UC-05 recurrence next-day.  
6. UC-06 capture, undo, offline queue.  
7. UC-07 plan confirm and cancel.  
8. UC-08 focus, interrupt, end.  
9. UC-09 emergency in and out.  
10. UC-10 filters and completed history.  
11. UC-11 health deny and cycle anchor.  
12. UC-13 factory reset, then confirm the plate is empty of old rows, then UC-01 again.  
13. UC-15 kill/relaunch on the hero and on a multi-day slice.

Widget, second-account, and on-device Live Activity rows (UC-04-M, UC-13-F, UC-08-B) need a device or a second simulator account. Simulator runs cover the rest.
