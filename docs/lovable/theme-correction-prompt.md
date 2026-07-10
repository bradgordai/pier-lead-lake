# Lovable prompt: correct the brand palette to Pier indigo (remove gold)

Paste this into Lovable after the current build. It is a theme-only change.

---

Update the theme only. Do not touch layout, typography, page structure, or business logic. Keep the dark-mode-first approach — the dark base is already close to Pier's palette.

We are correcting the brand colours. The current build uses a gold accent (#FFAE00) that came from a product deck, not Pier's master brand. Replace it everywhere with Pier indigo. There must be **no gold (#FFAE00) anywhere** in the app after this change.

## Design system tokens (define these and use them everywhere)
Set up a proper token-based theme with these exact values, then reference the tokens rather than raw hex:

- Background base (dark): **#030F42**
- Elevated surfaces (cards, panels, sidebars): **#11144D**
- Primary / CTA: **#1D237A**
- Primary hover: **#2B3299**
- Text primary: **#FFFFFF**
- Text muted: **#B4B8D6** (light indigo-tinted grey)
- Border / divider: **#2A2E5F**

## Specific replacements
- Primary button background: change from gold #FFAE00 to indigo **#1D237A**.
- Primary button hover: slightly brighter indigo **#2B3299**.
- Focus rings and interactive accents: white or light indigo, **not gold**.
- Chart accent colours (if any): use an indigo scale (e.g. tints/shades of #1D237A), not gold.
- Any token, variable, or class named "accent", "brand", "brand-accent", or similar: point it at **#1D237A**.
- Links, active nav states, selected rows, badges, toggles, and any other element currently using the gold accent: switch to **#1D237A** (or white/#B4B8D6 where a neutral reads better).

## Do NOT change
- Layout, spacing, grid, or component structure.
- Typography (Inter throughout).
- The dark-mode base shading, beyond aligning it to the tokens above.
- Semantic status colours that are not brand gold — e.g. the Priority pill scale (P0 grey, P1 red, P2 amber, P3 green, OoS light grey, Competitor purple) stays as is. Note: P2 "amber" is a status colour, not the brand gold, so leave it.

## After the change
Confirm that a global search for `#FFAE00` (and any "gold" token name) returns zero results, and that primary buttons, focus rings, and accents now render Pier indigo.
