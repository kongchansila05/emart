# EMART24

Flutter client for EMART24 marketplace.

## Run Modes

Use Dart defines to switch between mock mode and hosted backend mode.

### 1) Mock mode (no backend required)

```bash
flutter run --dart-define=USE_MOCK_API=true
```

### 2) Hosted backend mode

```bash
flutter run \
  --dart-define=USE_MOCK_API=false \
  --dart-define=API_BASE_URL=https://your-domain.com/api
```

If `USE_MOCK_API` is not set, it defaults to `false`.
If `API_BASE_URL` is not set, it defaults to `https://api.e.2m-sy.com/api`.

## Backend Hosting Checklist

- Hosting/domain: `https://your-domain.com` with valid HTTPS certificate.
- API base path: `/api` (or update `API_BASE_URL` to match your backend).
- CORS: allow app/web origins and `Authorization`, `Content-Type` headers.
- Auth routes available:
  - `POST /auth/register/client`
  - `POST /auth/login`
  - `POST /auth/refresh-token`
  - `POST /auth/google/login/client`
  - `POST /auth/google/register/client`
  - `POST /auth/otp/send`
  - `POST /auth/otp/verify`
- Core data routes available:
  - `GET /users/me`
  - `GET /posts`
  - `POST /posts`
  - `GET /categories`
  - `GET /categories/active`
  - `GET /categories/:id/sub-categories`
  - `GET /banners` or `GET /banners/active`
- Reverse proxy: forward `/api/*` to app server and keep request body limits high enough for image upload.
- Image upload limits: align server max body size with client limits.

## Docs

- Google Sign-In setup guide: `docs/google-sign-in-setup.md`
- Backend go-live guide: `docs/backend-hosting-setup.md`
- Firebase phone auth setup guide: `docs/firebase-phone-auth-setup.md`


Platform  Firebase App Id
web       1:597563194177:web:082290cbaabe6db1487fc0
android   1:597563194177:android:652defe33cc2e9eb487fc0
ios       1:597563194177:ios:ee47a8d2f7f12242487fc0
macos     1:597563194177:ios:ee47a8d2f7f12242487fc0
windows   1:597563194177:web:c45cea430c41fc3f487fc0


keytool -list -v -alias androiddebugkey -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android