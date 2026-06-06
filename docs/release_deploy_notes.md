# Release and Deploy Notes

This app deploys static catalog files from the repository root plus Vercel API routes for personal series tags. Vercel serves `series_library.html`, `series_library.css`, frontend JavaScript modules, and the committed public JSON payloads.

## Before Committing

Run:

```powershell
npm test
```

For frontend interaction changes, also run the optional browser regression check when Playwright is available:

```powershell
npm run test:browser
```

## Data Changes

When data logic or catalog content changes:

1. Rebuild the database and public JSON:

   ```powershell
   npm run migrate
   ```

2. Commit the updated `series_library.db`, `series_library_data.json`, and `series_library_details.json` if they changed.

3. Run `npm test`.

## Personal Tag Sync

Plex sync is a CLI-only personal-state workflow. It updates `Available` from Plex library presence and `Seen` from fully watched episode counts; it does not change catalog JSON.

Dry-run locally:

```powershell
npm run plex:sync
```

Apply locally:

```powershell
npm run plex:sync:apply
```

To push synced tags to production, write through `/api/series-state` or use the production database connection. Preserve existing `Wishlisted` values when syncing Plex state.

## Deploy

Push the tested branch to the Vercel-connected remote. The public page uses committed static files only; SQLite is not deployed.
Personal tags require a hosted Postgres connection in Vercel via `DATABASE_URL` or `POSTGRES_URL`.

```powershell
git push
```

## Quick Checks

- `/` rewrites to `/series_library.html`.
- Public JSON is committed and schema-valid.
- `.vercelignore` excludes source/cache folders, generated files, SQLite DB files, and local metadata.
- No browser update controls for catalog data are present.
- The only mutable public API is `/api/series-state` for `Wishlisted`, `Available`, and `Seen`.
