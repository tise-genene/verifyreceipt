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
# edit .env and set VERIFY_API_KEY (unless running local-only mode)
..\scripts\bootstrap_backend.ps1
```

## Local "better-verifier" mode (CBE PDF receipts)

The backend can verify some providers without calling the upstream verifier.

When enabled, local verifiers act as a **fallback**: the backend will try the upstream verifier first and, if it fails or returns a non-success result, it will try the local verifier.

Currently implemented:

- **CBE**: fetches the public PDF at `https://apps.cbe.com.et:100/?id=<reference>` and extracts fields.
- **Telebirr**: fetches the public receipt page at `https://transactioninfo.ethiotelecom.et/receipt/<invoiceNo>` and extracts fields.

Enable it with:

- `LOCAL_CBE_RECEIPT_ENABLED=true`
- Optional: `CBE_RECEIPT_BASE_URL=https://apps.cbe.com.et:100/`

Or for Telebirr:

- `LOCAL_TELEBIRR_RECEIPT_ENABLED=true`
- Optional: `TELEBIRR_RECEIPT_BASE_URL=https://transactioninfo.ethiotelecom.et/receipt/`

When this local mode is enabled, **`VERIFY_API_KEY` is not required for CBE reference verification**.

Quick test:

```powershell
$env:LOCAL_CBE_RECEIPT_ENABLED='true'
python -m uvicorn app.main:app --app-dir "$PWD" --host 127.0.0.1 --port 8080
```

Then:

```powershell
$body = @{ provider = 'cbe'; reference = 'FT...' } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:8080/api/verify/reference' -ContentType 'application/json' -Body $body
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
