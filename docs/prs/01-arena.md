Adds a server-authoritative bomb arena on an original 15×13 grid. Players submit movement, bomb and ready intents; the server validates them and determines explosions, collisions and match outcomes. Colyseus rooms support up to eight authenticated players.

Validation: TypeScript strict checking, ESLint, production build and 13 tests passed locally in Node 22. Tests cover gameplay, a real eight-client WebSocket match, rejected credentials, room capacity, HTTP payload limits and rate limiting.

Run `npm ci`, `npm run lint`, `npm test` and `npm run build`. This is the first PR in the phase-1 stack; API, Godot client and deployment follow in separate PRs.
