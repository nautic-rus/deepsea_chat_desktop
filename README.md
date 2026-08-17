# DeepSea Chat Desktop

Installers are distributed through GitHub Releases, and the repository no longer stores binary installers.

Use [`scripts/publish-release.sh`](/Users/spiridovich/Documents/GitHub/deepsea_chat_desktop/scripts/publish-release.sh) to publish a release from the dist folder in the sibling repo:

`/Users/spiridovich/Documents/GitHub/deepsea_chat/dist`

The script uploads only `.exe` and `.dmg` files from the top level of `dist`.

Example:

```bash
GITHUB_TOKEN=... ./scripts/publish-release.sh 0.2.7
```
