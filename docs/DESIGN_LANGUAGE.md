# SQLite Vault Design Language

SQLite Vault uses two deliberately separate material layers.

1. **Content surfaces** use restrained neumorphic depth: system grouped colors, paired soft shadows, subtle borders, large continuous corners, and high information density.
2. **Functional floating controls** use iOS 26 Liquid Glass. Glass is not applied to every card.

## Interaction rules
- Vertical scrolling always wins over decorative card motion. Ordinary content cards must never install a zero-distance drag recognizer.
- Touch feedback is immediate but small: slight scale/haptic response, no blocking animation.
- Springs are interruptible and used for snapping physical controls, not as decoration on every state change.
- Runtime locale changes use a no-animation transaction. The app may re-layout, but it must not interpolate between layouts in different languages.

## Language dial
The language selector is a full-screen modal material layer with three vertical detents. A single circular knob represents the selected language. Near each detent, motion is magnetically resisted and release snaps with a spring. Small distance increments emit brief rigid haptic ticks, while a detent crossing emits a stronger impact. The control uses a globe symbol rather than language-specific book glyphs.

Reduced Motion removes spring travel. Reduced Transparency replaces glass-heavy surfaces with solid system material while preserving hierarchy and control semantics.
