# Privacy and publication gate

Only explicitly selected configuration is eligible for Git. `.gitignore` is a guardrail, not a secret detector: ignored files can still be copied into a Nix store source. Keep all secrets **outside the clone**.

## Secrets strategy

Application credentials remain under private user state with restrictive permissions, provided at runtime. No age/SOPS key, encrypted secret, SSH key, password/hash, token or certificate is managed here. A future sops-nix/agenix adoption needs a separate design and must keep decryption identities private.

Obsidian MCP expects a private `~/.config/obsidian-mcp/environment` and `ca.pem`. The environment should supply `OBSIDIAN_API_KEY`, `OBSIDIAN_HOST`, `OBSIDIAN_PORT`, and `OBSIDIAN_CA_BUNDLE` pointing to a trusted local certificate. Generate the API key and certificate through your local Obsidian plugin; restrict the environment file to the owning user. Do not paste real values into Nix, Git, documentation or build logs. Loopback addresses appearing in modules are local service defaults, not a private network map. The package import test uses an explicitly inert placeholder, not a login credential.

## Review process

Run `python3 scripts/privacy-scan.py` before staging and again with `--staged` after staging. Findings contain paths/categories/line numbers, never matched values. Inspect flagged files locally. Keyword references such as sudo's password requirement, environment variable names, session targets and inert build placeholders are expected false positives; they are not evidence of a secret by themselves.

Review `git status`, `git diff`, `git diff --cached`, `git ls-files`, and unexpected binary/large files. The scanner checks common credential assignments/formats, private paths, IP/MAC/UUID, emails/phone-like values, dangerous filenames and binary content. Its history mode scans every reachable commit's blobs. This is heuristic detection, not a proof that arbitrary prose or proprietary data is safe.

`docs/FILE-INVENTORY.md` classifies every file intended for tracking. Initial history is empty unless the owner chooses to commit. Git staging is prepared only after review. At the initial audit handoff, no remote was configured and no push had been performed.

The private deployment wrapper lives in a sibling directory with restricted directory permissions and contains filesystem identifiers. Never publish it or place it beneath the public clone. The public scanner also rejects local-path flake inputs. Git identity and account authentication should be configured by the owner before committing.

## Independent scanner

The flake check also runs pinned Gitleaks with its default rules. `.gitleaks.toml` extends those rules with one narrow, reviewed exception: the exact `XF86Calculator` key symbol in `config/ambxst/binds.json` is not an API key. Both the path and exact value must match; the file and generic API-key rule are not globally excluded. This follows Gitleaks' [rule-specific allowlist configuration](https://github.com/gitleaks/gitleaks#configuration).

The local heuristic scanner separately covers all UTF-8 files, including formats Gitleaks may ignore by default, and rejects unexpected binaries and files larger than 256 KiB. Identifier searches and human review supplement token detection. No scanner establishes copyright or proves the absence of secrets.
