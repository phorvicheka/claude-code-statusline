# Contributing: Adding New Elements

To add a new element to the statusline:

1. Add a `SHOW_*` toggle in the Configuration section at the top of `statusline.sh`
2. Parse the JSON field in the single-jq block
3. Write a `render_*()` function (check `SHOW_*` flag, check data, print or return empty)
4. Add `render_*` to the `L1`/`L2`/`L3` arrays

See [configuration.md](configuration.md) for toggle and layout details, and [anatomy.md](anatomy.md) for the element reference and line layout structure.
