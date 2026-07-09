# API Mock

`apps/api/mock_server.py` is a dependency-free local API mock for roadmap API
contracts.

Run:

```bash
python3 apps/api/mock_server.py --port 8765
```

Implemented endpoints:

- `GET /health`
- `GET /api/parts`
- `POST /api/avatars`
- `GET /api/avatars/:id`
- `PATCH /api/avatars/:id`
- `GET /api/avatars/:id/config`
- `GET /api/avatars/:id/model?format=glb`
- `GET /api/avatars/:id/model?format=vrm`
- `POST /api/export_jobs`
- `POST /api/vrm_export_jobs`

The server stores avatars in memory and resets on restart. It is not a
production backend, but it gives SDK, widget, and API contract work a real HTTP
target before the hosted service exists.
