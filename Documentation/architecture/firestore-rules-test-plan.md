# Firestore security rules — test plan (Phase 6.5)

**Status:** Spec / CI-ready checklist (emulator harness TBD)

## Principles

- Users may only read/write `users/{uid}/**` where `uid == request.auth.uid`
- No list queries outside own tree
- Unauthenticated reads/writes denied
- App Check enforced at proxy; rules still required for direct SDK access

## Cases

| ID | Setup | Operation | Expect |
|----|-------|-----------|--------|
| R1 | Auth as A | read `users/A/tasks/x` | allow |
| R2 | Auth as A | read `users/B/tasks/x` | deny |
| R3 | None | write `users/A/tasks/x` | deny |
| R4 | Auth as A | create task missing uid field | deny if rule requires match |
| R5 | Auth as A | write `users/A/inbox_items/y` | allow |
| R6 | Auth as A | write `users/A/health_summaries/z` | allow |
| R7 | Auth as A | delete own task | allow |
| R8 | Auth as A | update foreign journal | deny |

## Local run (when harness exists)

```bash
firebase emulators:exec --only firestore \
  "npm test --prefix tools/firestore-rules-tests"
```

## CI gate

- Fail PR if rules change without test update  
- Nightly full emulator suite on staging project stub  

## Notes

Keep client able to function offline solely on SQLite/outbox so rules denials don't brick the app UI.
