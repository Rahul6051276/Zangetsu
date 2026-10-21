# TV Home Catalogue Navigation

## Goal

Move TV catalogue selection to a simple Home header and remove the bulky navigation surface, without changing the phone UI or catalogue behavior.

## Agreed design

- Use the app mark alone at the far left of the Home header; do not show the Zangetsu wordmark text.
- Center three TV-only choices: **Anime**, **Movies & TV**, and **Source Catalogue**.
- Show the existing **Source · [source] ▾** picker at the right only while Source Catalogue is selected. Keep source switching on the existing source-selection path.
- Remove extra header actions such as search/notification icons from this selector row.
- Replace the large floating/boxed navigation surface with simple standalone navigation icons. Keep their existing destinations and D-pad accessibility.
- Hide the navigation icons completely while focus is in Home content. Moving Left from Home reveals navigation; moving Right back to content hides it completely.
- Keep Home hero, catalogue rows, source loading, preferences, and all phone layouts/logic unchanged.

## Implementation boundaries

Reuse the existing TV shell, catalogue preference/source-switcher code, and current focus handling. Do not add a new setting, persistence, backend change, navigation destination, dependency, or new catalogue behavior.

## Verification

- Widget-test the three catalogue choices, conditional source picker, and left-to-open/right-to-hide navigation behavior.
- Run focused TV Home and shell tests, then `flutter analyze` on changed files.
- Build the TV-preview APK and verify D-pad focus on the connected device if available.

## Risks

The main risk is making navigation difficult to discover or leaving focus stranded when it hides. The rail must remain reachable with Left, return focus to Home with Right, and preserve existing destinations. The phone shell must remain untouched.
