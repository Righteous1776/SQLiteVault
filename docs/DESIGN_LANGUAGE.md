# SQLite Vault Design Language — V0.2.1

SQLite Vault is a data console first. The visual system must increase confidence and hierarchy without reducing data density.

## 1. Layer model

1. **Background** — system grouped background with a subtle accent gradient.
2. **Data surfaces** — restrained Neumorphic panels using soft paired shadows and system colors.
3. **Inset working surfaces** — SQL editor and similar tools use an inset treatment to communicate direct manipulation.
4. **Floating controls** — iOS 26 Liquid Glass for primary/secondary actions and selected navigation states only.

## 2. Motion model

- Immediate feedback on interaction.
- Springs use short response and high damping; no decorative bounce by default.
- State-changing SF Symbols use `.contentTransition(.symbolEffect(.replace))` to provide a native Morphicons-like transition.
- Respect Reduce Motion by falling back to direct state changes or opacity transitions.

## 3. Typography

- System font only.
- Rounded display face is reserved for console-level metrics/headlines.
- SQL and raw values use monospaced system faces.
- Large headings use tighter tracking; body copy remains neutral.

## 4. Data safety in UI

- Read-only state must remain visible in SQL Console and database overview.
- Destructive actions stay in context menus or explicit destructive affordances.
- Styling must never make a destructive control resemble a safe primary action.

## 5. References

- Apple-style interaction reference: `emilkowalski/skills`, `skills/apple-design/SKILL.md`.
- Morphicons inspiration: universal stroke icon morphing with spring physics. Native implementation here uses SF Symbols and SwiftUI rather than embedding the web library.
