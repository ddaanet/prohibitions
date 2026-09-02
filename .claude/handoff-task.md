## Current task

Cutting the release carrying the `deny-ask-user-question` three-channel split: the deny reason holds the verdict alone, `additionalContext` carries the inline-questions recovery, `systemMessage` the curt human line. Design decision *A deny splits three ways by audience* records the shape and the CC 2.1.258 probe behind it.

The sequence is `/gitlore:push`, then `ddaa:preflight`, then `just release patch` if preflight comes back clean. Preflight aborts on the resting ` M memory` gitlink — that path is excluded by design, other dirty paths are genuine findings.
