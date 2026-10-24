Adds a playable Godot 4.4.1 client with original pixel geometry, WASD/arrow movement, bombs, readiness controls and authoritative match results. The client authenticates against FastAPI and connects directly to the pinned Colyseus protocol through a small adapter.

Validation: Godot import, script parsing and main-scene runtime passed. Two actual headless Godot adapters completed authentication, room join, movement, bomb placement and winner verification against the Docker stack. A graphical run under Xvfb produced this screenshot:

![Godot gameplay](https://raw.githubusercontent.com/huynhcntt2012/codexserver/suni/03-client/docs/images/gameplay.png)

Original visuals and Godot copyright notices are included. No external game assets are used. Run `GODOT=/path/to/godot python3 scripts/check-godot.py`; the smoke script requires the API and arena services. This PR depends on the account API PR.
