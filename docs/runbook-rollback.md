# Runbook: Rollback to Pre-Hardening Checkpoint

Tag `checkpoint/plan-d-pre-hardening` marks the working-tree state captured at
the start of Phase 1 sync/recovery hardening. Parent: `6a61235` on
`feat/plan-d-premium`. Branch: 3 checkpoint commits on `hardening/phase-1-base`.

## Contents captured
- 10 Supabase migrations (0005-0013, 0016) + all `lib/core/` sync+crypto WIP
- Android launcher icons, splash, Nunito fonts, `caregivers_screen.dart`
- `.gitignore` adds `.claude/worktrees/`; `.DS_Store` removed from index

## Inspect (non-destructive)
```sh
git switch --detach checkpoint/plan-d-pre-hardening
git describe --tags HEAD   # must print: checkpoint/plan-d-pre-hardening
```

## Restore on a new branch (preferred)
```sh
git switch -c rollback/from-pre-hardening checkpoint/plan-d-pre-hardening
flutter pub get && flutter analyze   # pre-existing issues expected
```

## Reset hardening branch back (destructive — controller approval only)
```sh
git switch hardening/phase-1-base
git reset --hard checkpoint/plan-d-pre-hardening
```

## Post-rollback verification
- `git describe --tags HEAD` == `checkpoint/plan-d-pre-hardening`
- `supabase/migrations/0016_grant_and_fix_rls.sql` exists
- `lib/features/caregivers/presentation/caregivers_screen.dart` exists
- `git ls-files .DS_Store` is empty
