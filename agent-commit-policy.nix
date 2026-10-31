# Shared commit authorship policy injected into every AI agent's global instructions
# (Claude Code CLAUDE.md, Mistral Vibe AGENTS.md, Antigravity CLI GEMINI.md).
# Takes the per-host git identity (flake extraSpecialArgs `git`).
{ name, email, ... }:
''
  ## Git Commits: Authorship & Sign-off (MANDATORY)

  - **Never** credit yourself or any AI agent/tool in a commit or PR: no `Co-authored-by:` trailers for Claude, Anthropic, Mistral, Vibe, Gemini, Antigravity, or any other AI; no `Signed-off-by:` lines for an AI; no "Generated with ..." / "🤖" footers in commit messages or PR descriptions.
  - **Every commit must be signed off by exactly:** `Signed-off-by: ${name} <${email}>` — and that must be the only `Signed-off-by:` trailer.
    - Use `git commit -s` when `git config user.name` / `user.email` already resolve to `${name}` / `${email}`; otherwise add it explicitly with `git commit --trailer "Signed-off-by: ${name} <${email}>"`.
    - Before finishing, verify with `git log -1 --format=%B` that the trailer is present exactly once and that no AI co-author/sign-off lines exist; amend if needed.
  - Do not change the git author/committer identity (`--author`, `git config user.*`) to an AI identity.
''
