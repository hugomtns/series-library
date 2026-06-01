# Release and Deploy Notes

This app deploys as static files from the repository root. Vercel serves `series_library.html`, `series_library.css`, frontend JavaScript modules, and the committed public JSON payloads.

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

## Deploy

Push the tested branch to the Vercel-connected remote. The public page uses committed static files only; SQLite is not deployed.

```powershell
git push
```

## Quick Checks

- `/` rewrites to `/series_library.html`.
- Public JSON is committed and schema-valid.
- `.vercelignore` excludes source/cache folders, generated files, SQLite DB files, and local metadata.
- No browser update controls or mutable data APIs are present.
