# AI Irrational Exuberance Research

Static publish package for a two-entry research site:

- Home: `index.html`
- AI supply-demand report: `ai-supply-demand.html`
- China factor report: `china-factor.html`

## Sync

```sh
ruby scripts/sync_china_factor.rb
```

The sync script copies local dependencies into `assets/`, injects a home link
into each report, and fails if a published page references files outside this
site directory.
