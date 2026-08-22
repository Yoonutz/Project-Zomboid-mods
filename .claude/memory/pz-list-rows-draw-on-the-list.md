---
name: pz-list-rows-draw-on-the-list
description: "A custom ISScrollingListBox doDrawItem must issue its draw calls on the LIST; drawing them on the parent window silently kills scrolling and shifts every row by the list's offset"
metadata:
  node_type: memory
  type: project
---

`ISScrollingListBox:doDrawItem(y, item, alt)` hands out a `y` measured from the top of
the list's own content (`ISScrollingListBox.lua:507`). Every `drawText` / `drawRect` call
resolves against whichever element it is invoked on, so a custom renderer must call them
on the list.

TwoManCrew's Orders briefing called them on the window instead, via a closure that
captured `window` and passed it as `self`. Three symptoms, all from that one choice, and
none of them looked like a drawing-target problem:

- **The scrollbar did nothing.** Scroll offset is applied to the list. Paint somewhere
  else and the offset never reaches the paint, so the bar moved and the text did not.
- **Rows landed a tab-strip too high and a pad too far left**, because window-relative
  0,0 is the title bar, not the top of the list.
- **The first rows were missing entirely.** The list sets a stencil over its own
  rectangle (`ISScrollingListBox.lua:504`) before the item loop, and that stencil is
  global render state, so it clipped away everything pushed above the list's top edge
  while leaving the rest looking almost plausible.

The fix is to pass the list in as a separate `surface` argument and draw through it,
keeping the window as `self` only for what the window owns - the font, the scale, the
text trimmer. Width comes from `surface:getWidth()`, and `SCROLLBAR_W` is subtracted only
when `surface:isVScrollBarVisible()` is true.

**Why:** the near-miss is the danger. Content still appeared, in the right order, in
roughly the right place, so it read as a layout or padding problem and drew three rounds
of fixes at the wrong layer. A dead scrollbar next to a custom `doDrawItem` is the tell.

**How to apply:**

- Any custom `doDrawItem` draws on the list argument, never on a captured parent.
- Suspect this first when a list scrolls visually but its contents do not move.
- Same trap for anything else the engine renders inside a stencil or a scroll offset.

Related: [[pz-ui-size-must-go-through-setters]], [[pz-verification-is-ingame-only]],
[[pz-vanilla-source-is-the-api-reference]].
