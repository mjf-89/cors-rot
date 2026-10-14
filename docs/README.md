# Docs

Records from the development of the in-page Tor client inside the Self Forming project, kept for
their security content. File paths in them refer to that project's layout:
`third-party/webtor-rs/` is now `build/patches/webtor-rs/` (patch, export allowlist) and `docs/`;
`libs/cors-rot/vendor/webtor/` or `apps/browser/vendor/webtor/` is `vendor/webtor/` here.

- `tor-client-security-remediation.md`: the original client's TLS and directory flaws and every fix
  (sections 1–10), with the remaining unaudited limits.
- `tor-client-recovery.md`, `tor-client-provenance.md`: build provenance and the first recovery pass.
