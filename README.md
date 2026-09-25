# AI-Luxreport

Static publish package for the **AI 产业与投资研究** series:

- Home: `index.html`
- AI supply-demand report: `ai-supply-demand.html`
- China factor report: `china-factor.html`
- FDE path index: `fde-search.html`
- FDE journey: `fde-journey.html`
- Direction-first nine: `fde-direction-nine.html`
- Aztec review: `fde-aztec.html`
- Short share: `waiting-for-overreaction/index.html`

Every public page uses `assets/research-series.css` for the shared series marker and
the return link to the research home. Keep page titles, body copy, conclusions, and
URLs unchanged when maintaining that shared chrome.

## Sync

```sh
ruby scripts/sync_china_factor.rb
ruby scripts/sync_short_share.rb
```

The sync scripts copy local dependencies into the publish repository and fail
if a published page references files outside its self-contained site directory.
