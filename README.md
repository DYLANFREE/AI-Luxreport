# AI-Luxreport

Static publish package for a two-entry research site and a standalone short share:

- Home: `index.html`
- AI supply-demand report: `ai-supply-demand.html`
- China factor report: `china-factor.html`
- Short share: `waiting-for-overreaction/index.html`

## Sync

```sh
ruby scripts/sync_china_factor.rb
ruby scripts/sync_short_share.rb
```

The sync scripts copy local dependencies into the publish repository and fail
if a published page references files outside its self-contained site directory.
