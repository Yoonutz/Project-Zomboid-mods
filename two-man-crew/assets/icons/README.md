# Two-Man Crew Icons

This folder contains generated source art and a preview sheet for the Two-Man
Crew UI icons.

Game-ready PNGs live in:

`Contents/mods/TwoManCrew/42/media/ui/`

Those shipped icons are exported as `512x512` plus matching `_16.png` variants.

They were `48x48` until 2026-08-22. The crew badge is resizable, and anything
larger than its source was the engine stretching 48 pixels to fill the space -
which reads as blur and no setting fixes. Exporting from the 1254px masters at
512 removes it, and costs about 40 KB per icon.

Re-export with a straight LANCZOS resize from `generated-sources/`; the framing
is the master's own, uncropped. The `_16.png` variants are unchanged.
