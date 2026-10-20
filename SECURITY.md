# Security policy

Photo is a development preview. Security fixes target the current `main` branch; no stable release or long-term support branch has been published.

## Report a vulnerability privately

Use **Security → Report a vulnerability** or [start a private vulnerability report](https://github.com/kuroiokami/photo/security/advisories/new). Do not disclose an exploitable issue in a public issue or pull request. If private reporting is temporarily unavailable, use GitHub Support rather than posting exploit details publicly.

Include the affected commit, macOS version, a minimal synthetic reproduction, expected impact and relevant redacted logs. Never attach credentials, private client photos, precise location metadata, catalogs or personal libraries. Maintainers handle reports on a best-effort basis; there is no guaranteed response time or bounty program.

## Project boundaries

Treat unsafe original-file writes, source-protection bypass, path traversal, symlink/replacement mistakes and destructive recovery behavior as security-relevant. Test only disposable copies. Source protection applies inside Photo; other software and forensic write blocking are outside its scope.

CI uses read-only permissions, immutable action pins, verified tool downloads and redacted secret scanning. These checks reduce risk; they do not establish that every vulnerability or secret has been found.
