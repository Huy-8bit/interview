# Docker Cheatsheet

- Image immutable layers; container = image + writable layer + process isolation.
- Multi-stage build; pinned digest; small runtime; non-root; read-only FS khi có thể.
- `.dockerignore`; copy dependency manifest trước để tận dụng cache; không bake secret.
- One main concern/process; stdout/stderr; graceful SIGTERM; health semantics rõ.
- Volume cho persistent/externalized data; container filesystem là ephemeral.
- Scan/sign/SBOM; rebuild để nhận security patch, không chỉ `apt upgrade` lúc start.
