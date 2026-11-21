# <ID> <TITLE>

<DATE>   baseline <SHA>

<The idea, the reasoning, the evidence: how you write it and how much is up to you. The reader of this page wants to know why you think it helps, what you saw, and which behaviors must not change.>

```json
<JSON>
```

`by` is the investigator's proposal this came from; the proposal review (`experiments/<ID>.proposal.review.md`) must be written by a different agent.
It lands only if `targets` get better and no other metric regresses. `allowed` lists the files that may change (`*` = any). `predict` is [baseline, prediction]; it is scored but does not affect landing.
`min_gain` can set a minimum gain for a target, e.g. `{"job": 0.02}`. This block is frozen once it first passes the gate.
