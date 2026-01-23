# verifyreceipt

Monorepo:

- `backend/`: FastAPI proxy that holds the upstream `x-api-key` and exposes app-friendly endpoints.
- `mobile/`: Flutter (Android) app (scaffolded via script once Flutter SDK is installed).

## Quick start

### 1) Backend (proxy)

```powershell
cd backend
..\scripts\bootstrap_backend.ps1
```

### 2) Mobile (Flutter)

Flutter SDK is required.

Run the app:

```powershell
cd mobile
flutter run
```

#### Backend base URL

By default, the app uses the deployed backend `https://verifyreceipt-backend.onrender.com`.

For local emulator testing, override via dart-define or the in-app **Server settings** (gear icon) to `http://10.0.2.2:8080`.

To point to your Render backend, run:

```powershell
cd mobile
flutter run --dart-define=API_BASE_URL=https://<your-service>.onrender.com
```
