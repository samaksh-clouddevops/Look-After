# Look After — GitHub Pages

Static site for product landing + privacy policy.

## URLs (after enable)
- Site: https://samaksh-clouddevops.github.io/Look-After/
- Privacy: https://samaksh-clouddevops.github.io/Look-After/privacy

## Enable Pages (one-time operator step)
1. Open the GitHub repo → **Settings** → **Pages**
2. **Build and deployment** → Source: **GitHub Actions**
3. Push/merge so `.github/workflows/pages.yml` runs  
   (branches: `main`, `master`, `feature/android-implementation`)
4. Or **Actions → Deploy GitHub Pages → Run workflow**
5. Confirm green deploy; open the privacy URL

## Files
- `index.html` — landing
- `privacy.html` — privacy policy (Play requirement)
- `.nojekyll` — raw static serve

## Keep in sync
`android/store/privacy-policy.html` mirrors `docs/privacy.html` for offline packaging.
Play listing references the Pages privacy URL.
