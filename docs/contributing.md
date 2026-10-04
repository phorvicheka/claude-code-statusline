# Contributing: Adding New Elements

To add a new element to the statusline:

1. Add a `SHOW_*` toggle in the Configuration section at the top of `statusline.sh`
2. Parse the JSON field in the single-jq block. Use the `g()` / `q` / `num()` helpers at the top of that program: every value must be reduced to a shell-quoted scalar (objects, arrays and `null` become empty) before `eval`, so one oddly shaped field can never abort the parse or inject shell code. Avoid `//` on booleans (it treats `false` as missing)
3. Write a `render_*()` function (check `SHOW_*` flag, check data, print or return empty)
4. Add `render_*` to the `L1`/`L2`/`L3` arrays
5. Add a case to `tests/run.sh` (a payload that shows the element, and one where it must be absent) and run `bash tests/run.sh`; also run `shellcheck -S warning statusline.sh install.sh tests/run.sh`

A renderer that can shrink to fit its row should be registered in `_is_flex()` and honour `_FLEX_BUDGET` (see `render_user_host`).

See [configuration.md](configuration.md) for toggle and layout details, and [anatomy.md](anatomy.md) for the element reference and line layout structure.
