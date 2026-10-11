# bcc-doorlocks

> Door locks for RedM on the **Feather Framework**. Staff create locks on any door; players open them with a job, a key item, by being on the door's allowed list, or by lockpicking.

Version **2.0.0** is the Feather port of BryceCanyonCounty's bcc-doorlocks 1.3.2. The menus, prompts, door hashes and restart rules are unchanged; access is decided on the server through Feather domains. Port details: [FEATHER_PORT.md](FEATHER_PORT.md).

## Features

- Up to 3 **feather-jobs** jobs per door (for example `sheriff`), optionally only while on duty.
- A key item per door (any **feather-inventory** item).
- A list of allowed characters per door (character UUIDs).
- Lockpicking with a `lockpick` item when a minigame resource runs.
- Doors kept open after a restart (`Config.KeepOpenOnRestart`).
- `/ManageDoorLocks` menu for door staff: create, edit and delete doors.
- A server API for other resources (housing, jails).

Every lock, unlock, edit and lockpick is checked on the server, including that the player stands near the door.

## Who can open a door

A player opens a locked door when **one** of these is true:

| Rule | Configured in | Checked through |
|---|---|---|
| Holds one of the door's jobs (on duty when `Config.JobAccess.requireOnDuty`) | Door menu | feather-jobs `CheckAssignment` |
| Carries the door's key item | Door menu | feather-inventory |
| Their character is on the door's allowed list | Door menu (server ID or character UUID) | feather-core session |
| Is door staff | See below | feather-authority |

**Door staff** (create, edit, delete and open every door):

- characters given the door role with `DoorlocksAdminGrant <server id>` (capability `staff.doorlocks.manage`);
- Feather Admin administrators and owners (`Config.Admin.staffCapabilities`, default `staff.admin.audit.search`).

## Requirements

Start these before `bcc-doorlocks`:

```cfg
ensure feather-mysql
ensure feather-core
ensure feather-character
ensure feather-notify
ensure feather-toolkit
ensure feather-menu-v2
ensure feather-inventory
ensure feather-organizations
ensure feather-authority
ensure feather-jobs
ensure feather-admin
ensure bcc-minigames      # optional, for lockpicking (or rsd_lockpick)
ensure bcc-doorlocks
```

Without a minigame resource the lockpick prompt is hidden.

## Installation

1. Put the folder in `resources/[bcc]/bcc-doorlocks` and add `ensure bcc-doorlocks` after the resources above.
2. Trust bcc-doorlocks in the Feather resources it calls (keep the entries already there):

   **feather-jobs/config.lua** (read job assignments):

   ```lua
   Access = {
       trustedReaders = { ['feather-jobs'] = true, ['feather-admin'] = true,
           ['bcc-doorlocks'] = true },
       -- other groups unchanged
   }
   ```

   **feather-authority/config.lua** (the door staff role and capability; all five lists):

   ```lua
   Access = {
       trustedReaders              = { --[[ ... ]] ['bcc-doorlocks'] = true },
       trustedCapabilityRegistrars = { --[[ ... ]] ['bcc-doorlocks'] = true },
       trustedRoleCreators         = { --[[ ... ]] ['bcc-doorlocks'] = true },
       trustedGrantors             = { --[[ ... ]] ['bcc-doorlocks'] = true },
       trustedAssigners            = { --[[ ... ]] ['bcc-doorlocks'] = true }
   }
   ```

3. Import [sql/install_items.sql](sql/install_items.sql) once, for the `lockpick` item.
4. Restart `feather-jobs`, `feather-authority`, then `ensure bcc-doorlocks`. Tables are created and old rows converted on start.
5. Run `DoorlocksReleaseSmokeTest` in the server console and expect every line to pass.
6. Give yourself the staff role: `DoorlocksAdminGrant <your server id>` (or use a Feather Admin administrator/owner character).

Jobs on a door must exist in feather-jobs. They are registered by the resource that owns them, for example bcc-society's job types (`doctor`, `gunsmith`, `blacksmith`, ...).

## Usage

- `/ManageDoorLocks` opens the door menu.
- **Create a door:** aim at the door with a gun, press **G**, then set its jobs, key item and allowed players.
- **Delete a door:** pick it from the list in the menu.
- Near a door, the prompts show **Lock/Unlock** and, when allowed, **Lockpick**.

### Keep selected doors open after restart

Add each door's database ID (`doorid` in the `doorlocks` table) to `Config.KeepOpenOnRestart`:

```lua
Config.KeepOpenOnRestart = { 12, 34 }
```

They are unlocked after the restart lock rules run and can still be locked during play.

## Configuration

See [config.lua](config.lua). The Feather-specific parts:

| Setting | Purpose |
|---|---|
| `Config.Admin` | Door staff capability and role, and the Feather Admin capabilities that also count as staff |
| `Config.JobAccess.requireOnDuty` | Job doors open only while that job is on duty |
| `Config.ServerDistanceCheck` | The server checks the player is near the door (needs OneSync) |
| `Config.LockPicking` | Minigame (`bcc_minigames` or `rsd_lockpick`), lockpick item, attempts |
| `Config.devMode.active` | Debug output; keep `false` on a live server |

## Server API

For other server resources (housing, jails). Character IDs are Feather character UUIDs; jobs are feather-jobs job keys.

```lua
local Doors = exports['bcc-doorlocks']:getDoorLocksAPI()

-- Create a door (doorInfo is the door hash table from the door list).
Doors:AddDoor(doorInfo, { 'sheriff' }, 'none', { characterId }, true)

-- Change an existing door.
local door = Doors:GetDoorById(12)
if door then
    door:UpdateAllowedJobs({ 'sheriff', 'marshal' })
    door:UpdateAllowedIds({ ownerCharacterId, guestCharacterId })
    door:UpdateKeyItem('jail_key')
    door:UpdateLockStatus(true)
end

-- All doors.
-- Each entry: { id, info, jobs, keyItem, locked, idsAllowed }; false when there are none.
for _, door in ipairs(Doors:GetAllDoors() or {}) do print(door.id, door.locked) end
```

The client exports `createDoor`, `deleteDoor`, `deleteSpecificDoor` and `addPlayerToDoor` still exist for staff tools, but they only work for door staff.

## Console

| Command | Purpose |
|---|---|
| `DoorlocksReleaseSmokeTest` | Read-only release check: dev mode off, Jobs trust, Authority role, no legacy rows, lockpick item |
| `DoorlocksAdminGrant <server id>` / `DoorlocksAdminRevoke <server id>` | Give or remove the door staff role |

## Credits

Original script by [BryceCanyonCounty](https://github.com/BryceCanyonCounty/bcc-doorlocks). Feather port by [BCC-FeatherFramework](https://github.com/BCC-FeatherFramework/bcc-doorlocks). Licensed GPL-3.0.
