# BCC Doorlocks: Feather port

**Status:** code complete on the development server (2026-10-08); not yet live-tested.
**Version:** 2.0.0 (from upstream bcc-doorlocks 1.3.2)
**Plan:** phase B1 of the [BCC on Feather master plan](https://github.com/BCC-FeatherFramework/bcc-feather-masterplan),
job consumer for the [Jobs master plan](https://github.com/FeatherFramework/feather-framework-docs/blob/main/feather-jobs/Feather_Jobs_Master_Plan.md) (J5).

The door menus, prompts, door hashes, jail-door seeding, restart rules and
translations stay as they were. What changed is who decides access, and that the
server now checks every request.

## What moved where

| Before (VORP) | Now (Feather) |
|---|---|
| `vorp_core` user, `charIdentifier` | `feather-core` session, character UUID |
| `Config.AllowedGroups` / `AllowedJobs` (`character.group`, `character.job`) | Authority capability `staff.doorlocks.manage` (role `staff.doorlocks.admin`), or Feather Admin administrators/owners through `Config.Admin.staffCapabilities` (`staff.admin.audit.search`) |
| Door jobs checked against `character.job` | `feather-jobs` `CheckAssignment` on the job key; on duty when `Config.JobAccess.requireOnDuty` |
| `vorp_inventory` `getItemCount` / `subItem` | `feather-inventory` `GetItemCount` / `RemoveItemByName` |
| `bcc-utils` RPC, prompts, 3D text, debug | `feather-core` RPC, `feather-toolkit` prompts and `DrawText3D`, local `DBG` |
| `feather-menu` (v1) | `feather-menu-v2` through `client/feather/menu_v2.lua` |
| Local `Locales` table | `feather-core` locales (`en_us`, `ro`, `pl`, `de`, `es`, `fr`), keys prefixed `bcc-doorlocks.` |
| `bcc-minigames` required | Optional: the lockpick prompt shows only while `bcc-minigames` (or `rsd_lockpick`) runs |

There is no VORP, `bcc-utils`, `oxmysql` or Menu v1 code left.

## Security fixes

The upstream resource trusted the client for everything. Now:

- Creating, editing, listing and deleting doors (`InsertIntoDB`, `UpdateDoorlock`,
  `GetDoorField`, `DeleteDoorlock`, `DeleteDoor`, `GetAllDoorlocks`,
  `AddPlayerToDoor`) require door staff on the server.
- Locking and unlocking check the door's jobs, key item and allowed characters on
  the server, and that the player stands near the door (`Config.ServerDistanceCheck`,
  needs OneSync; skipped when the server cannot see positions).
- A lockpick result is accepted only once, for the same door, within two minutes
  after the server started that lockpick for a player who holds the item. A client
  can no longer unlock any door by sending `lockpicked = true`.
- A failed lockpick removes the item only after a server-started lockpick.
- Submitted jobs, key items and character IDs are validated and bounded.

## Data changes

- `ids_allowed` holds character UUIDs. Staff type a connected player's server ID or
  a character UUID; the server stores the UUID.
- On start, rows are converted once: `'none'` jobs become `[]`, and VORP numeric
  character IDs are dropped (they cannot be mapped to UUIDs). The console prints how
  many were dropped; re-add those players in the door menu.
- `jobsallowedtoopen` holds feather-jobs job keys (for example `sheriff`).

## Staff check fix (2026-10-11)

The Feather Admin fallback called a feather-admin `GetStaffRole` export that does not exist, so
Admin administrators and owners were silently not door staff (only `DoorlocksAdminGrant` worked).
It now evaluates `Config.Admin.staffCapabilities` through feather-authority, as bcc-society and
bcc-banks do.

## Trust needed in other resources

| Resource | Setting | Entry |
|---|---|---|
| feather-jobs | `Config.Access.trustedReaders` | `['bcc-doorlocks'] = true` |
| feather-authority | all five `Config.Access` lists | `['bcc-doorlocks'] = true` |

Restart feather-jobs and feather-authority after changing them, then bcc-doorlocks.

## Console

| Command | Purpose |
|---|---|
| `DoorlocksReleaseSmokeTest` | Read-only release check: dev mode off, Jobs trust, Authority role, no legacy rows, lockpick item |
| `DoorlocksAdminGrant <server id>` / `DoorlocksAdminRevoke <server id>` | Give or remove the door staff role for that player's character |

In game: `/ManageDoorLocks` (staff) opens the door management menu.

## For other resources

The client exports `createDoor`, `deleteDoor`, `deleteSpecificDoor` and
`addPlayerToDoor` now only work for door staff. Gameplay resources (for example
bcc-housing) should use the server API instead:
`exports['bcc-doorlocks']:getDoorLocksAPI()` (`GetDoorById`, `GetAllDoors`, `AddDoor`,
and per door `UpdateAllowedIds`, `UpdateAllowedJobs`, `UpdateKeyItem`, `UpdateLockStatus`).

## Remaining work

1. Live test: create a door, lock/unlock as staff, as a job holder on and off duty,
   with a key item, as an allowed character, and as a stranger (denied).
2. Double doors, jail-door seeding, restart lock rules and door deletion.
3. Lockpicking once a minigame resource is installed. Import `sql/install_items.sql` for the
   `lockpick` item (also in bcc-craft).
4. Move door access to `feather-access` when that domain exists (master plan Phase 3).
