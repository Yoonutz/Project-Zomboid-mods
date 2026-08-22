---
name: pz-ui-size-must-go-through-setters
description: "PZ hit-tests the mouse against the Java object; assigning self.width/self.height in Lua never reaches it, so always resize through setWidth/setHeight"
metadata:
  node_type: memory
  type: project
  originSessionId: 22191151-f982-426b-8b95-9c0e6caccbb7
  modified: 2026-08-22T09:18:50.112Z
---

Project Zomboid keeps every UI element's mouse rectangle on the **Java** object. Lua's
`self.width` / `self.height` are only what the drawing code reads. The Java rectangle is
updated in exactly one place - `ISUIElement:setWidth` / `setHeight`, which forward to
`javaObject:setWidth/setHeight` (verified at `client/ISUI/ISUIElement.lua:1136-1160`).

**A raw `self.width = n` therefore resizes the picture and not the hitbox.** The Java
rectangle keeps whatever size the element had when `addToUIManager()` created it.

This shipped in TwoManCrew 0.2.0 and produced three separate-looking bugs from one cause:

- the widget could not be clicked outside its old top-left corner,
- dragging "snapped out" as soon as the pointer left the stale rectangle, because PZ then
  delivers `onMouseUpOutside` and the drag ends,
- an always-expanded preference made it permanent rather than intermittent.

**Why:** it fails silently and asymmetrically. Everything looks right, and only mouse input
misbehaves - so it reads as a drag bug, a hover bug and a click bug rather than one resize bug.

**How to apply:**

- Resize only through `setWidth`/`setHeight`. Never assign the fields directly.
- Prefer a **fixed** element rectangle and vary only what is painted inside it. A size that
  never changes cannot desync; hover-to-expand needs no resize at all.
- Implement `onMouseMoveOutside` whenever `onMouseMove` drags something. A fast drag outruns
  the element, and without the outside handler motion stops being delivered anywhere - vanilla
  duplicates the movement in both (`client/ISUI/ISCollapsableWindow.lua:206-236`).
- `onMouseUpOutside` ends a real drag too, so it must save state, not discard it.

Related: [[pz-vanilla-source-is-the-api-reference]].
