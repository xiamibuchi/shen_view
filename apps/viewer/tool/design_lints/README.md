# ShenView design lints

This package keeps all presentation pages aligned with `docs/design/spec.md`. It is
loaded through `custom_lint` from the application root and checks four boundaries:

- semantic theme colors instead of raw `Colors.*` or `Color.*` values;
- shared form components instead of raw Material form controls;
- Fluent UI System Icons instead of the legacy `Icons` namespace;
- shared typography, control, menu, and slider styles instead of inline styles.

The legacy migration is complete and there is no per-file allowlist. Only the
shared component and theme directories are foundation layers permitted to
implement the underlying Flutter controls, colors, and styles.

Run the rules directly with:

```powershell
flutter pub run custom_lint
```
