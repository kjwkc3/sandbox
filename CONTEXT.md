# Sandbox Roguelite ARPG

A multiplayer roguelite action RPG built in Odin. Hobby project focused on learning — no ship date.

## Language

**Ascension**:
The core progression loop. Players climb floors, complete objectives, and reach the next floor. Death ends the run.
_Avoid_: Run, playthrough, campaign

**Floor**:
A single level in an ascension, consisting of connected rooms. Each floor has an objective (clear rooms, defeat a boss, time trial, etc.)
_Avoid_: Level, stage, map

**Room**:
A self-contained combat encounter within a floor. Rooms are connected by doors. Players fight enemies, then doors unlock to adjacent rooms.
_Avoid_: Arena, encounter

**Hub**:
A safe zone at floor 0 and every ~10 floors. Players can trade, buy gear, reform groups, and see other players. No combat occurs in hubs.
_Avoid_: Town, base, lobby

**Objective**:
The goal for a given floor. Varies by floor — may require clearing all rooms, defeating a boss, completing a time trial, etc.
_Avoid_: Quest, mission, task

**Class**:
A character archetype with 5 skills. Each class has a primary stat it scales. Start with 2-3 classes. Examples: Warrior (toughness), Mage (wisdom), Ranger (agility).
_Avoid_: Build, archetype

**Downed**:
A state when a player's life hits 0. Teammates have a few seconds to revive them. If not revived in time, the death is permanent.
_Aavoid_: Dead, eliminated, killed

**Meta-progression**:
Account-wide bonuses earned based on class played and floors reached. Stats persist across runs and characters. Caps prevent farming early floors.
_Avoid_: Permanent upgrades, legacy bonuses

**League**:
A temporary play period with account wipes. Keeps the economy and progression fresh. Players opt in voluntarily.
_Avoid_: Season, wipe, reset

**Gear Slot**:
The equipment positions on a character: head, chest, main hand (or two-handed), offhand (if not two-handed), hands, legs, feet, 2x rings, 2x earrings, 1x trinket.
_Avoid_: Equipment slot, item slot

**Trinket**:
A special gear slot for items with unique effects. May or may not be combat-focused — could provide utility, mobility, or other niche benefits.
_Avoid_: Artifact, relic, accessory

**Skill Tree**:
A branching progression system per class. Players earn skill points during a run and spend them to unlock new skills or enhance existing ones. A player equips 5 active skills from their tree at any time.
_Avoid_: Talent tree, ability tree

**Personal Loot**:
Drops that only the killing player can see initially. Loot becomes shared after a waiting period or if the player leaves the room. Party leader can configure loot rules at run start.
_Avoid_: Private loot, individual loot

**Storage**:
Item slots that persist across runs. Unlocked by progress milestones (e.g., 1 slot at start, another at floor 20). Allows saving strong gear for future characters.
_Avoid_: Stash, vault, bank

**Tile**:
A single floor element in a room. Tiles form the walkable and non-walkable areas. Characters are not locked to tiles — they can exist on multiple tiles simultaneously.
_Avoid_: Grid cell, square
