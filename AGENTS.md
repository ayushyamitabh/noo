# Agent guidance

This repo's agent guidance lives in [`CLAUDE.md`](CLAUDE.md) and the
topic files it links in `.claude/context/`. It applies to every coding
agent (Codex included), not just Claude - read it before making changes.

The step most often missed:

- **Before pushing**, update `distribution/whatsnew/whatsnew-en-US` (the
  Google Play release note, max 500 characters) to cover every user-facing
  change since the latest `Release-*` tag, and commit it with the push.
  See CLAUDE.md "Before pushing" for the full rule.
