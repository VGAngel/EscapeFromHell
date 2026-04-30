# `secrets/`

Local-only credentials used by the Android build pipeline.

Anything in this folder **except** `.gitignore`, this README and
`keystore.env.example` is ignored by git. Don't loosen that.

## Bootstrap

```bash
# 1. Generate keystores (one-time per dev machine for debug, once
#    ever for release — back the release keystore up offline).
./scripts/build/create_keystore.sh

# 2. Copy the env template and fill in the real password.
cp secrets/keystore.env.example secrets/keystore.env
$EDITOR secrets/keystore.env

# 3. Verify the build can find everything.
./scripts/build/build_android.sh --validate-only
```

## Release keystore

The release keystore is **the** identity of the app on the Play
Store. If it's lost, the app can never be updated under the same
listing — you'd have to publish a new app and migrate users.

After creation, back up `secrets/release.keystore` and the password
to **at least two** offline locations (e.g. encrypted USB + 1Password
vault). Never email it, never paste in chat, never commit.

CI uses GitHub Actions secrets (`EFH_RELEASE_KEYSTORE_BASE64`,
`EFH_RELEASE_KEYSTORE_PASS`) — see `.github/workflows/android.yml`
when the CI step lands.
