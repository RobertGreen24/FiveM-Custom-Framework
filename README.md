# Nexus Framework

A custom, drop-in FiveM roleplay framework: a single core engine plus a full suite of
gameplay resources, each with its own modern NUI written in plain HTML/CSS/JS (no build
step, no npm, no bundler).

Everything lives under `resources/[nexus]/` and uses the `nx_` prefix, the
`nexus:...` event namespace and colon-style exports (`exports.nx_core:getPlayer(src)`).

```
resources/[nexus]/
├── nx_core            # engine: players, characters, data layer, callbacks, logs, admin
├── nx_multicharacter  # character slots, creation/deletion and the picker NUI
├── nx_spawn           # spawn selector with camera fly-in
├── nx_hud             # vitals, money, job, speedometer, fuel and voice
├── nx_inventory       # grid inventory, hotbar, weapons and containers
├── nx_appearance      # character creator, clothing, barber, tattoos, outfits
├── nx_vehicles        # ownership, keys, fuel, seatbelts, cruise and hotwire
├── nx_garages         # public/fleet garages and police impounds
├── nx_vehicleshop     # dealerships with finance, trade-ins and test drives
├── nx_banking         # accounts, transfers, history and society accounts
├── nx_shops           # 24/7 stores plus sell points
├── nx_jobs            # duty points, salaries, job centre and stashes
├── nx_police          # MDT, cuffs, jail, fines, evidence and dispatch
├── nx_ems             # medical MDT, revive/treat, hospitals and supplies
└── nx_chat            # channels, ranges, adverts and emergency calls
```

## Requirements

| Requirement | Notes |
| --- | --- |
| FXServer (game build 3095+) | `sv_enforceGameBuild 3095` is set in the example config |
| [oxmysql](https://github.com/overextended/oxmysql) | the only hard dependency; the DB layer wraps its promise API |
| MySQL 8 / MariaDB 10.6+ | import `sql/nexus.sql` once |
| OneSync | required for entity state bags used across vehicles and inventory |

Optional integrations are detected at runtime: `pma-voice` (proximity voice on the HUD)
and `screenshot-basic` (photo capture).

## Installation

1. **Database** — import the schema, then create a user for the server:

   ```bash
   mysql -u root -p < sql/nexus.sql
   ```

2. **Resources** — copy the `[nexus]` folder into your server's `resources/` directory:

   ```
   resources/
   ├── [nexus]/
   │   ├── nx_core/
   │   └── ...
   └── [standalone]/oxmysql/
   ```

3. **Server config** — copy `server.cfg.example` to your server root and edit it. At a
   minimum set `sv_licenseKey`, `mysql_connection_string` and your admin licence in the
   ACE block. Resource start order matters: `nx_core` first, `nx_vehicles` before
   `nx_garages`/`nx_vehicleshop`, and `nx_inventory` before `nx_shops`.

4. **Permissions** — the admin ladder is 0–4 and each action maps to an ACE:

   ```
   add_ace group.admin nexus.admin allow
   add_ace group.moderator nexus.admin.kick allow
   add_principal identifier.license:YOUR_LICENSE group.admin
   ```

5. Start the server. On first join the character creator opens; the spawn selector
   follows, and the HUD takes over once you are in the world.

## How it works

**Players and characters.** One `nx_players` row per licence owns up to N characters
(`nx_characters`). Money, job, inventory, vehicles, outfits and phone data all hang off
`char_id`. `Nexus.GetPlayer(source)` returns the live player object server-side
(`:notify()`, `:getMeta()`, `:setMeta()`, `:removeMoney()`, `:hasJobPermission()`).

**Events.** Server→client framework events are `nexus:client:*`, client→server are
`nexus:server:*`. Resource-local traffic uses the resource's own namespace, e.g.
`nx_police:mdtSearch`. Shared utilities are exposed globally on the server
(`Nexus.DB`, `Nexus.Log`, `Nexus.Society`, `Nexus.Utils`) and through exports
(`exports.nx_core:getDutySources(job)`, `exports.nx_inventory:addItem(...)`).

**Database.** `Nexus.DB.{defer,update,scalar,single,insert,query}` are thin oxmysql
wrappers, so nothing outside `nx_core/server/database.lua` talks to the driver directly.

**UI.** Every panel is a self-contained `nui/` folder using plain HTML/CSS/JS and the
usual `fetch('https://<resource>/nx:...')` bridge. There is no build step: edit the file,
restart the resource.

## Configuration

Each resource ships a `config.lua` at its root and they are all plain Lua tables — the
common ones you will want to touch:

| Resource | Config | What it controls |
| --- | --- | --- |
| `nx_core` | `shared/config.lua` | starting money, character slots, pay tick, locale |
| `nx_vehicles` | `config.lua` | key items, fuel burn/cost, seatbelts, hotwire, plate price |
| `nx_garages` | `config.lua` | garage and impound locations, fees, fleets |
| `nx_vehicleshop` | `config.lua` | catalogue, finance rates, trade-in percentage |
| `nx_jobs` | `config.lua` | duty points, salary, tax, grade bonus |
| `nx_police` / `nx_ems` | `config.lua` | jail, fines, cells, hospitals, fees |
| `nx_appearance` | `config.lua` | shops, prices, uniforms, outfit slots |
| `nx_chat` | `config.lua` | channels, ranges, adverts, announcements |

## Status

Implemented and syntax-checked against the whole repository:

| Area | Resources |
| --- | --- |
| Core | `nx_core` |
| Character & world | `nx_multicharacter`, `nx_spawn`, `nx_hud`, `nx_appearance` |
| Economy & items | `nx_inventory`, `nx_banking`, `nx_shops`, `nx_jobs` |
| Vehicles | `nx_vehicles`, `nx_garages`, `nx_vehicleshop` |
| Public services | `nx_police`, `nx_ems`, `nx_chat` |

Still to come (their hooks already exist in `nx_core` and the gameplay scripts, and the
matching `ensure` lines sit commented out in `server.cfg.example`): `nx_ui`,
`nx_weathersync`, `nx_mechanic`, `nx_phone`, `nx_admin` and `nx_loadingscreen`.

## Contributing

Keep new resources to the same shape — `fxmanifest.lua`, `config.lua`, `server/main.lua`,
`client/main.lua` and an optional `nui/` folder — and lint Lua before committing.
