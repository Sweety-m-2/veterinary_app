# AI_LOG.md

## Tools used and purpose

- **ChatGPT:** used to understand the assignment, review Flutter/Dart implementation choices, explain dataset loading and passing `DrugDataset` into the CRI screen, and draft documentation.
- **Other tools:** `Codex AI Agent`

## Estimated AI contribution

AI assistance was used for explanation, debugging, code suggestions, and documentation. Estimated AI-generated or AI-rewritten share of the final code: approximately 40%. This should count code retained from AI suggestions, not merely the number of prompts. I reviewed and adapted suggestions, but I am responsible for understanding and verifying the submitted implementation.

## Case 1 — Unsafe CRI values from the future dataset

**Prompt/context:** I needed the CRI screen to follow Part C while the app still used v14; the assignment says Dopraxine is introduced by the v15 update.

**Relevant AI suggestion:** An earlier CRI implementation included hardcoded values for Dopraxine (40 mg/mL and a dog range of 5–10 mcg/kg/min) and calculated a result directly from them.

**Why it was wrong for the current state:** Those values belong to the v15 update, while the bundled app dataset was v14. Hardcoding them would bypass the dataset source of truth and could show a result unsupported by the active dataset.

**What I did instead:** I kept the existing CRI form UI but changed the Calculate action to clear any result and display a professional message that CRI data is unavailable in the currently loaded dataset. No CRI calculation is performed until a supported dataset supplies the required information.

## Case 2 — Passing `activeDataset` without defining it

**Prompt/context:** I wanted the CRI screen to receive a `DrugDataset` instance through an `activeDataset` parameter.

**Relevant AI suggestion:** An earlier navigation example used `CriCalculatorScreen(activeDataset: activeDataset)` without first showing where the `activeDataset` variable was created or how the dataset was loaded.

**Why it was wrong/incomplete:** In `main.dart`, there was no variable named `activeDataset`, so Dart reported an “Undefined name 'activeDataset'” error. Passing a constructor argument does not create or load the dataset object.

**What I changed:** I used a `FutureBuilder` pattern in `HomeShell` to load the bundled dataset and pass the resulting `DrugDataset` instance to the CRI screen. The parent widget is responsible for handling the loading and error states before the dataset is used.

**Verification:** I ran `flutter analyze` and `flutter test`. All 63 tests passed, and the analyzer reported no errors, although it identified five warnings/info notices. These checks provide useful verification but do not, by themselves, prove that every dataset-loading or navigation scenario is correct.

## Case 3 — Code-review lesson about rounding

**Prompt/context:** The assignment asks for a review of a function that rounds a calculated volume to one decimal place.

**Relevant AI-assisted finding:** Rounding a small positive volume to one decimal place can display it as `0.0 mL`, potentially hiding the fact that the calculated value was non-zero. Display rounding should not alter the underlying calculation value.

**Decision:** Calculation precision and display formatting should be handled separately. The display precision should be chosen so that small values are not misleadingly represented as zero, while the underlying calculation retains its precision.

**Implementation and verification status:** I reviewed the formatting logic and identified the need to preserve sufficient decimal places for small values. The available test run passed all 63 tests, but that result alone does not establish that small-volume formatting is covered. I will claim the rounding issue is resolved only after confirming the final formatting implementation and adding or verifying tests for small values and display precision limits.

## A decision I changed my mind about

Initially, the CRI screen was calculating using constants copied from the v15 example. I changed my approach after checking the assignment's versioning requirement: the current v14 dataset does not contain the Dopraxine CRI record, so the screen should demonstrate the requested inputs but refuse to calculate until the required data is available. This is safer and makes the UI behavior consistent with the active dataset.

## Verification status

- `flutter test`: passed; all 63 tests passed in the test run performed on 13 October 2026.
- `flutter analyze`: completed with 5 warnings/info notices and no reported errors. The notices include an unused `_parsePositive` declaration, two deprecated form-field `value` usages, and two `print()` calls in `tool/probe.dart`.
- Review the remaining analyzer notices and rerun both checks before the final submission.
- Review the final repository and Git history to ensure this log accurately describes the retained AI-assisted code and the actual implementation.
- The prompt/context descriptions above are summaries, not verbatim transcripts.


