# Security notes

This is a local inference deployment package, not a hardened multi-tenant
gateway.

- `--api-key` is a shared bearer token. It is not user authentication and does
  not provide per-user quotas or audit trails.
- Do not expose the NInfer ports directly to the public Internet. Put a reverse
  proxy, VPN, or private network boundary in front of them.
- Change the placeholder key before using the service on a shared LAN.
- The server does not terminate TLS by itself; use a TLS-terminating proxy if
  traffic crosses an untrusted network.
- Request logs can contain prompts and generated content. Keep them on a
  protected volume and apply your own retention policy.
- Model weights, compiled binaries, API keys, and raw client logs must never be
  committed to this repository.

If you find a packaging or documentation issue, open an issue without including
secrets, private prompts, or internal addresses.
