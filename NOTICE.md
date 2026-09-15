# Attribution and asset scope

Original workstation configuration, local scripts and documentation are offered under MIT (LICENSE). External applications are fetched at locked revisions and keep their upstream licenses; their repositories, compiled artifacts, wallpapers and bundled assets are not vendored here.

`config/hyprland.lua` derives from Hyprland's example configuration and retains upstream BSD-3-Clause terms for that material. See `licenses/Hyprland-BSD-3-Clause.txt` and [upstream license](https://github.com/hyprwm/Hyprland/blob/main/LICENSE). Local workstation changes remain covered by MIT without overriding upstream conditions.

`config/ghostty/shaders/green-crt.glsl` is preserved from the workstation's locally configured CRT theme. Existing implementation documentation describes it as a locally added shader; no external shader pack was copied. The generated GTK/Qt files and Ambxst JSON describe local preferences and colors, not application code. This provenance review did not reconstruct authorship history beyond the existing configuration records.

The custom rmpc SVG and wallpaper images were excluded because redistribution provenance was not established. Font packages and application artwork are fetched through their packages rather than copied into this repository. The rmpc desktop entry retains its application metadata and uses a generic icon.
