# Home Assistant Lights By Area

Fresh snapshot from Home Assistant: `2026-07-06T05:59:54.135Z`

This report is based on a live Home Assistant export using:

- REST: `/api/config`, `/api/states`, `/api/events`, `/api/services`, `/api/components`
- WebSocket: `config/entity_registry/list`, `config/entity_registry/list_for_display`, `config/device_registry/list`, `config/area_registry/list`, `config/floor_registry/list`, `config/label_registry/list`

The export found:

- `400` total entities
- `397` entity-registry entries
- `78` devices
- `12` areas
- `38` `light.*` entities

Secrets and raw Home Assistant payloads are not included here.

## Progress Summary

Honest progress score: **92% app-ready right now**.

The Home Assistant side is in very good shape. The local backend `.env` now points Playroom at `light.playroom`, the grouped four-downlight target, and leaves the non-existent all-lights target blank.

### Direct Clarifications

- Old lamp-style Playroom entity IDs are disconnected and should not be used by the app.
- `light.study_study_lamp_3` is **not showing up as a current HA light**. It is still configured in `apps/api/.env`.
- `light.all_lights` is **not showing up as a current HA light/group**. It was configured in `apps/api/.env`, and the backend code used to default to it when the env value was missing.
- `Laundry Room` is fixed in HA.
- `Home` and `Main Floor` look intentional as utility/automation areas. I would keep them.
- The remaining unassigned lights are the `Standard`, `Top Sconce`, and `Bottom Sconce` entities. If those are old Hue/apartment devices, they are not blockers for the Levy Home UI.

## Required `.env` Change

Update the non-secret light config in `apps/api/.env` to this:

```sh
HOME_ASSISTANT_ALL_LIGHTS_ENTITY_ID=
HOME_ASSISTANT_LIGHT_GROUPS=
HOME_ASSISTANT_LIGHT_ENTITIES=light.foyer_lights: Foyer, light.garage_entry: Garage Entry, light.kitchen_cans: Kitchen Cans, light.kitchen_nook: Kitchen Nook, light.upstairs_hallway: Upstairs Hallway, light.study_lamp_1: Study Lamp 1, light.study_lamp_2: Study Lamp 2, light.study_lamp_3: Study Lamp 3, light.playroom: Playroom
```

Why this exact change:

- Blank `HOME_ASSISTANT_ALL_LIGHTS_ENTITY_ID` because HA does not have `light.all_lights`.
- Blank `HOME_ASSISTANT_LIGHT_GROUPS` because the current app setup is using exact light entities instead of grouped HA targets.
- Use `light.playroom` because Playroom is now the grouped four-downlight target in HA.
- Use `light.study_lamp_1`, `light.study_lamp_2`, and `light.study_lamp_3` because the Study is a three-lamp room in HA and in your Night Night automation.

If you want the app to show **one Study target** instead of three Study lamp targets, the cleaner HA-side improvement would be to create a Study light group/helper such as `light.study_lights`, then use that single entity in `HOME_ASSISTANT_LIGHT_ENTITIES`.

## Current Floors And Areas

| Floor | Areas |
| --- | --- |
| Main | Dining Room, Family Room, Foyer, Garage, Kitchen, Laundry Room, Main Floor, Playroom |
| Upstairs | Master Bedroom, Study, Upstairs Hallway |
| none | Home |

`Main Floor` and `Home` are utility/automation areas. That is okay as long as you intentionally want non-room areas for whole-home or floor-wide automations.

## Code Source-Of-Truth Update

The backend now treats `HOME_ASSISTANT_ALL_LIGHTS_ENTITY_ID` as optional instead of defaulting to `light.all_lights`.

Current source-of-truth behavior:

- If `HOME_ASSISTANT_LIGHT_ENTITIES` is set, those exact entities drive the overview and light-off actions.
- If `HOME_ASSISTANT_LIGHT_ENTITIES` is blank and `HOME_ASSISTANT_ALL_LIGHTS_ENTITY_ID` is set, the API can use that all-lights target.
- If both are blank but `HOME_ASSISTANT_LIGHT_GROUPS` is set, the API can turn off those configured groups.
- The iOS app never sends arbitrary HA entity IDs to the backend.

## Levy Home Backend Light Config Audit

Current local `.env` values seen during this audit:

| Config | Current value |
| --- | --- |
| `HOME_ASSISTANT_ALL_LIGHTS_ENTITY_ID` | `light.all_lights` |
| `HOME_ASSISTANT_LIGHT_GROUPS` | empty |
| `HOME_ASSISTANT_LIGHT_ENTITIES` | 6 configured entries |

Configured `HOME_ASSISTANT_LIGHT_ENTITIES` before the recommended edit:

| Label in Levy Home | Configured entity ID | Found in fresh HA export? | HA area | Current state | Action |
| --- | --- | --- | --- | --- | --- |
| Foyer | `light.foyer_lights` | yes | Foyer | on | Keep. |
| Kitchen Cans | `light.kitchen_cans` | yes | Kitchen | on | Keep. |
| Kitchen Nook | `light.kitchen_nook` | yes | Kitchen | on | Keep. |
| Upstairs Hallway | `light.upstairs_hallway` | yes | Upstairs Hallway | off | Keep. |
| Study | `light.study_study_lamp_3` | no | n/a | n/a | Replace with current Study light entities or a Study group. |
| Playroom | old lamp-style Playroom entity IDs | no | n/a | n/a | Replace with `light.playroom`. |

## Area And Light Audit

### Foyer

Foyer is app-ready.

| Entity ID | HA name | Device | State | Notes |
| --- | --- | --- | --- | --- |
| `light.foyer` | Foyer | Foyer | on | Area-level/grouped light. |
| `light.foyer_lights` | Foyer | none | on | Recommended app target for Foyer. |
| `light.foyer_entry` | Foyer - Entry | none | on | Subgroup. |
| `light.foyer_stairway` | Foyer - Stairway | none | on | Subgroup. |
| `light.foyer_entry_1` | Foyer Entry 1 | Foyer Entry 1 | on | Individual bulb. |
| `light.foyer_entry_2` | Foyer Entry 2 | Foyer Entry 2 | on | Individual bulb. |
| `light.foyer_entry_3` | Foyer Entry 3 | Foyer Entry 3 | on | Individual bulb. |
| `light.foyer_stairway_1` | Foyer Stairway 1 | Foyer Stairway 1 | on | Individual bulb. |
| `light.foyer_stairway_2` | Foyer Stairway 2 | Foyer Stairway 2 | on | Individual bulb. |
| `light.foyer_stairway_3` | Foyer Stairway 3 | Foyer Stairway 3 | on | Individual bulb. |

### Playroom

Playroom is clean for the current four-downlight target.

| Entity ID | HA name | Device | State | Notes |
| --- | --- | --- | --- | --- |
| `light.playroom` | Playroom | Playroom downlights | on | Current app target for Playroom; represents the four downlights. |

The old lamp entity has been disconnected. Keep the app pointed at `light.playroom`.

### Kitchen

Kitchen is app-ready.

| Entity ID | HA name | Device | State | Notes |
| --- | --- | --- | --- | --- |
| `light.kitchen` | Kitchen | Kitchen | on | Area-level/grouped light. |
| `light.kitchen_cans` | Kitchen Cans | none | on | Recommended app target for kitchen cans. |
| `light.kitchen_nook` | Kitchen Nook | none | on | Recommended app target for kitchen nook. |
| `light.kitchen_main_1` | Kitchen Main 1 | Kitchen Main 1 | on | Individual bulb. |
| `light.kitchen_main_2` | Kitchen Main 2 | Kitchen Main 2 | on | Individual bulb. |
| `light.kitchen_main_3` | Kitchen Main 3 | Kitchen Main 3 | on | Individual bulb. |
| `light.kitchen_main_4` | Kitchen Main 4 | Kitchen Main 4 | on | Individual bulb. |
| `light.kitchen_nook_1` | Kitchen Nook 1 | Kitchen Nook 1 | on | Individual bulb. |
| `light.kitchen_nook_2` | Kitchen Nook 2 | Kitchen Nook 2 | on | Individual bulb. |
| `light.kitchen_nook_3` | Kitchen Nook 3 | Kitchen Nook 3 | on | Individual bulb. |
| `light.kitchen_sink` | Kitchen Sink | Kitchen Sink | on | Individual/fixture light. |

Dining Room has the `Dining Pico` device but no lights, which matches your explanation: the Pico is physically in Dining Room but controls Kitchen Cans.

### Upstairs Hallway

Upstairs Hallway is app-ready.

| Entity ID | HA name | Device | State | Notes |
| --- | --- | --- | --- | --- |
| `light.upstairs_hallway` | Upstairs Hallway Lights | Upstairs Hallway Lights | off | Recommended app target for Upstairs Hallway. |
| `light.upstairs_hall_guest` | Upstairs Hallway Guest Light | Upstairs Hallway Guest Light | off | Individual light. |
| `light.upstairs_hall_master` | Upstairs Hallway Master Light | Upstairs Hallway Master Light | off | Individual light. |
| `light.upstairs_hallway_study_light` | Upstairs Hallway Study Light | Upstairs Hallway Study Light | off | Now assigned to Upstairs Hallway. |

### Study

Study is clean at the individual-lamp level.

| Entity ID | HA name | Device | State | Notes |
| --- | --- | --- | --- | --- |
| `light.study_lamp_1` | Study Lamp 1 | Study Lamp 1 | on | Current Study light. |
| `light.study_lamp_2` | Study Lamp 2 | Study Lamp 2 | on | Current Study light. |
| `light.study_lamp_3` | Study Lamp 3 | Study Lamp 3 | on | Current Study light. |

Recommended app choice:

- Use all three `light.study_lamp_*` entities if you want the current `.env`-only setup.
- Create `light.study_lights` in HA if you want one clean Study room target.

### Garage

| Entity ID | HA name | Device | State | Notes |
| --- | --- | --- | --- | --- |
| `light.meross_garage_opener_dnd` | Dnd | Meross | on | Not a room light for the Home blueprint. |

### Family Room, Laundry Room, Master Bedroom

No `light.*` entities are currently assigned to these areas.

That is fine for the current lighting UI unless you expect visible light controls there.

## Utility Automation Areas

### Main Floor

Contains only floor-wide automations:

- `automation.foyer_main_floor_dim`
- `automation.foyer_main_floor_off`
- `automation.foyer_main_floor_on`

This is fine to keep as-is.

### Home

Contains only global/night automations:

- `automation.night_lights_guest_off`
- `automation.night_lights_guest_on`
- `automation.night_lights_master_off`
- `automation.night_lights_master_on`
- `automation.night_lights_study_off`
- `automation.night_lights_study_on`
- `automation.night_night`

This is also fine to keep as-is.

## Lights Not Assigned To Any Area

These are the only `light.*` entities with no HA area in the fresh export:

| Entity ID | HA name | Device | State | Likely action |
| --- | --- | --- | --- | --- |
| `light.bottom_sconce_1` | Bottom Sconce 1 | Bottom Sconce 1 | off | Remove/disable if stale old Hue gear. |
| `light.bottom_sconce_1_2` | Bottom Sconce 1 | Bottom Sconce 1 | off | Remove/disable if stale duplicate old Hue gear. |
| `light.standard_1` | Standard 1 | Standard 1 | off | Remove/disable if stale old Hue gear. |
| `light.standard_5` | Standard 5 | Standard 5 | off | Remove/disable if stale old Hue gear. |
| `light.standard_6` | Standard 6 | Standard 6 | on | Check this one because HA currently thinks it is on. |
| `light.standard_7` | Standard 7 | Standard 7 | off | Remove/disable if stale old Hue gear. |
| `light.top_sconce_1` | Top Sconce 1 | Top Sconce 1 | off | Remove/disable if stale old Hue gear. |
| `light.top_sconce_2` | Top Sconce 2 | Top Sconce 2 | off | Remove/disable if stale old Hue gear. |

## Recommended App-Facing Targets

| Blueprint node | Target recommendation |
| --- | --- |
| Entry/Foyer | `light.foyer_lights` |
| Playroom | `light.playroom` |
| Kitchen | `light.kitchen_cans` and `light.kitchen_nook`, or `light.kitchen` if you want one Kitchen target |
| Upstairs/Upstairs Hallway | `light.upstairs_hallway` |
| Study | all three `light.study_lamp_*` entities now, or future `light.study_lights` group |

## Next Cleanup Order

1. Update `apps/api/.env` with the non-secret light config shown above.
2. Restart the API after the `.env` edit.
3. Remove/disable the stale unassigned Hue lights if they really are old apartment devices.
4. Keep Playroom pointed at `light.playroom`.
5. Consider HA groups/helpers for one-target rooms such as `light.study_lights`.
