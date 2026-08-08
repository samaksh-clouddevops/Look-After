# Look After — GitHub Pages

Static site for product landing + privacy policy.

## URLs (after enable)
- Site: https://samaksh-clouddevops.github.io/Look-After/
- Privacy: https://samaksh-clouddevops.github.io/Look-After/privacy

## Enable Pages (one-time)
1. Open the GitHub repo → **Settings** → **Pages**
2. **Build and deployment** → Source: **GitHub Actions**
3. Merge/push to a branch covered by `.github/workflows/pages.yml`
   (`main`, `master`, or `feature/android-implementation`)
4. Run workflow **Deploy GitHub Pages** (or push a `docs/**` change)
5. Confirm green deploy; open the privacy URL

## Files
- `index.html` — landing
- `privacy.html` — privacy policy
- `.nojekyll` — raw static serve

## App link
Android Privacy screen opens:
`https://samaksh-clouddevops.github.io/Look-After/privacy`
