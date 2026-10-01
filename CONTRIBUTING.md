# Contributing to Noo

Thanks for your interest in improving Noo. Bug reports, ideas, and pull
requests are welcome.

## Before you start

- For anything bigger than a small fix, open an issue first so we can agree on
  the approach before you spend time on it.
- Read [`CLAUDE.md`](CLAUDE.md) and the topic files in
  [`.claude/context/`](.claude/context): architecture, server integration,
  styling, and code standards. They apply to human and AI contributors alike.
- Never include real server URLs, usernames, app passwords, or personal files
  in issues, tests, or screenshots.

## Setup

```bash
flutter pub get
flutter run
```

You need a Nextcloud server to sign in to. A throwaway local instance is best
for testing anything destructive (delete, move, trash).

## Making a change

1. Branch from `main`.
2. Keep the change focused; unrelated cleanup belongs in its own PR.
3. Run the checks:

   ```bash
   flutter analyze
   flutter test
   ```

4. Format only the files you touched (`dart format <files>`), not the whole
   tree.
5. If you changed architecture, server integration, styling conventions, or
   standards, update the matching file in `.claude/context/` in the same PR.
6. Open a pull request and fill in the template.

## Commit messages

Use the repository's template so history stays consistent:

```bash
git config commit.template .gitmessage
```

Write an imperative, sentence-case summary of 72 characters or fewer, then a
blank line and a short explanation of *why* when it isn't obvious.

## License of contributions

Noo is licensed under the [PolyForm Shield License 1.0.0](LICENSE). By
submitting a contribution you confirm that you wrote it (or have the right to
submit it), and you license it to the maintainer and everyone who receives the
project under those same terms. You also grant the maintainer the right to
relicense the project, including your contribution, in the future.

## Security

Please do not file security problems as public issues. Email
[hello@ayushya.dev](mailto:hello@ayushya.dev) with the details and I'll
respond as soon as I can.
