# <project>

Written by the owner, read by the agent before it starts. Commands and rules are in `explore.toml`; this file holds only what that cannot express.

- **What to improve**: <one sentence>
- **Priorities** (by weight): <the scenarios that hurt users most>
- **Out of scope**: <directions that are excluded>
- **Stop**: <a target value; or after N rounds; or after K rounds with no landing>
- **Must not change**: <output, interfaces, formats, consistency with other platforms. Whatever can be written as a command goes into the invariants in `explore.toml`; the rest goes here>
- **Forbidden shortcuts**: <special-casing which fixtures, data or names counts as cheating>
- **What the eval data covers and does not cover**: <regions, sources, sizes, which tuning it was used for. Every metric to improve needs at least one dataset that can show a difference; if there is none, add data first and open no experiment>
- **What environment is measured**: <simulator / small inputs / dev machine. How it differs from the product and how far to discount the conclusions>
- **Repository rules**: <test scope, directories not to touch, actions to ask about first>
