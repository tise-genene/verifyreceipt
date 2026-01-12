# Backend proxy (FastAPI)

This service keeps the upstream Verifier API key out of the mobile app and provides a stable contract for the Flutter client.

## Your API (what the app calls)

- `POST /api/verify/reference`
- `POST /api/verify/receipt`
- `GET /health`

### Verify by reference

`POST /api/verify/reference`

```json
{
  "provider": "telebirr|cbe|dashen|abyssinia|cbebirr",
  "reference": "FT123...",
  "suffix": "1353",
  "phone": "09..."
}
```

Notes:

- `suffix` is needed for `cbe` and `abyssinia` (account suffix).
- `phone` is needed for `cbebirr`.

### Verify by receipt (upload fallback)

`POST /api/verify/receipt` as `multipart/form-data`:

- `image`: file
- `provider`: optional (`telebirr` or `cbe` recommended; upstream image endpoint supports these reliably)
- `suffix`: optional (required for CBE image verification)

## Run locally (PowerShell)

```powershell
cd backend
copy .env.example .env
# edit .env and set VERIFY_API_KEY
..\scripts\bootstrap_backend.ps1
```

## Deploy on Render

This repo includes a Render blueprint at [render.yaml](render.yaml).

1. Push this repo to GitHub.
2. In Render: **New +** → **Blueprint** → select the repo.
3. Set environment variable `VERIFY_API_KEY` (required).
4. Deploy.

Optional env vars:

- `RATE_LIMIT_ENABLED` (default `true`)
- `RATE_LIMIT_PER_MINUTE` (default `60`)

Render will run:

- Build: `pip install -r requirements.txt`
- Start: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`

After deploy, check `https://<your-service>.onrender.com/health`.

## Important upstream constraints

- Telebirr verification may work reliably only from Ethiopia (upstream limitation noted in their docs).
