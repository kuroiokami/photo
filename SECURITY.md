# Security policy

Photo is a development preview. Security fixes target the current `main` branch; no stable release or long-term support branch has been published.

## Report a vulnerability privately

Use **Security → Report a vulnerability** or [start a private vulnerability report](https://github.com/kuroiokami/photo/security/advisories/new). Please keep vulnerability details out of public issues and pull requests.

Include the affected commit, macOS version, a minimal synthetic reproduction, expected impact and relevant redacted logs. Never attach credentials, private client photos, precise location metadata, catalogs or personal libraries. Reports are handled as maintainer time allows.

## Project boundaries

Please report issues that could cause unsafe writes to originals, bypass source protection, access unintended files or make recovery destructive. Use disposable copies for reproductions. Photo’s source protection covers operations inside Photo.

CI uses read-only permissions, immutable action pins, verified tool downloads and redacted secret scanning. These checks reduce risk; they do not establish that every vulnerability or secret has been found.
