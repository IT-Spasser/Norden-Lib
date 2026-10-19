# Migrating to 2.0 (NLib -> norden_lib)

2.0.0 renames the library. Nothing else changes behaviour.

| Before | After |
| --- | --- |
| resource `NLib` | resource `norden_lib` |
| `ensure NLib` | `ensure norden_lib` |
| `@NLib/imports.lua` | `@norden_lib/imports.lua` |
| `exports['NLib']` | `exports['norden_lib']` |
| `nlib` global | `norden_lib` |
| convars `nlib_*` | `norden_lib_*` |
| events `NLib:*` / `nlib:*` | `norden_lib:*` |
| ACE `nlib.*` | `norden_lib.*` |
| `@nlib/shared` | `@norden_lib/shared` |
| CSS classes `.nlib-*` | `.norden-*` |

Consumers pin `norden_lib_min_version '2.0'`. Rename the resource folder, update the
manifest dependency and every `exports[...]` call, then restart.
