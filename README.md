# rtl_433 Home Assistant add-ons

This is a collection of Home Assistant add-ons that work with [rtl_433](https://github.com/merbanan/rtl_433).

* [How to add this add-on repository to your Home Assistant install](https://home-assistant.io/hassio/installing_third_party_addons/)
* Use `https://github.com/rtl-433-hass/rtl_433-hass-addons` as the URL for the repository.

Full add-on documentation is published at <https://rtl-433-hass.github.io/rtl_433-hass-addons/latest/>.

## Running the Development Version

- First, follow the tutorial at [Tutorial: Making your first add-on](https://developers.home-assistant.io/docs/add-ons/tutorial/) to learn how to build a basic addon.
- Use `git` to clone this repository same `addons` folder used in the tutorial.
- Make changes to the code, or use `git` to checkout branches to test.
- Remember to to [reload](https://developers.home-assistant.io/docs/add-ons/tutorial/#i-dont-see-my-add-on) and reinstall the addon to rebuild the Docker containers to see any changes.

## Release Process

All development happens on the `main` branch. The `-next` addons are built automatically on every push to `main`, while stable addons are only built when a release tag is created.

Releases are automated with [release-please](https://github.com/googleapis/release-please), driven by [Conventional Commits](https://www.conventionalcommits.org/). Version numbers and `CHANGELOG.md` are derived from commit messages — there is no manual version bump.

### Automatic Builds

| Event | What gets built | Version |
|-------|-----------------|---------|
| Push to `main` | `-next` addons only | `next` |
| Daily schedule | `-next` addons only | `next` |
| Tag push (`v*`) | Stable addons only | From `config.json` |

### Creating a Release

1. Merge changes to `main` using Conventional Commit messages (`feat:`, `fix:`, etc.).
2. release-please opens (and keeps updating) a **release PR** that bumps the version in [rtl_433/config.json](rtl_433/config.json) and updates `CHANGELOG.md`.
3. Merge the release PR. release-please then tags the release (`v<semver>`, e.g. `v0.1.1`) and creates a GitHub Release, which triggers the stable addon build.

That's it! No branch reconciliation needed. Stable users see "Update Available" when the new version is published.

## Pull request documentation previews

Netlify builds the documentation using `netlify.toml` and publishes `site/`.
The build uses Python 3.14 and `docs/requirements.txt`, then runs
`mkdocs build --strict` from the repository root. The preview opens the branch's
current documentation directly, without the published version directories.

To enable previews, create a Netlify project by importing this GitHub repository,
select `main` as the production branch, and keep Deploy Previews enabled for pull
requests. Netlify reads the build settings from `netlify.toml` once it is merged.
Each PR gets a URL such as `https://deploy-preview-123--your-project.netlify.app`.
No additional GitHub Actions workflow or Netlify API token is required.
The existing GitHub Pages workflow continues to publish the versioned docs;
Netlify also publishes `main` at its own `netlify.app` URL.

See Netlify's [repository setup guide](https://docs.netlify.com/start/quickstarts/deploy-from-repository/)
and [Deploy Preview documentation](https://docs.netlify.com/deploy/deploy-types/deploy-previews/).
