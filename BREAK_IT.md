# BREAK_IT.md

## Purpose

This document reviews potential failure cases in the veterinary dose calculator, the protections intended to handle them, and the evidence needed to verify those protections.

The dataset values used for this assignment are fictional and must not be used for clinical decisions. A passing test suite does not establish clinical safety.

## Failure cases and verification plan

| Failure / attack case | Current protection or status | Test / evidence needed |
|---|---|---|
| Missing dose for the selected species | The calculation service is intended to reject unavailable species-dose data. Confirm the behavior for the selected drug and species in the current implementation. | Add or verify a unit test asserting that unavailable data produces a clear error or unavailable state and no calculated result. |
| Inverted dose range (`min > max`) | The domain model and calculation service contain validation logic for dose ranges. Confirm that invalid ranges are rejected before calculation. | Add or verify a test with an inverted range and assert that no result is produced. |
| Ambiguous percentage concentration (`10%`) | The concentration parser is intended to reject ambiguous percentage concentrations rather than assume a conversion to mg/mL. | Add or verify a test showing that an ambiguous concentration is rejected and no calculation proceeds. |
| Zero or invalid concentration | The calculation service checks concentration usability. Confirm that zero and invalid concentrations are rejected before division. | Add or verify tests for zero, negative, missing, and malformed concentrations; assert that no `NaN` or infinity result is displayed. |
| Whitespace, case differences, and species aliases | Normalization logic exists for drug and species identifiers. Verify that normalization handles expected aliases without merging distinct drug records. | Test documented examples such as trailing whitespace in a drug name and supported dog/cat aliases. |
| Invalid weight input | Weight parsing and validation are implemented in the dose-calculation flow. Confirm the accepted formats and boundaries in the current code. | Add or verify tests for empty input, invalid text, zero, negative values, decimal commas, decimal points, and supported weight units. |
| Rounding hides a small calculated volume | Display formatting must not alter the underlying calculation value. Small-volume display behavior still requires explicit verification. | Add or verify tests for small positive volumes and values near display precision limits. Confirm that a non-zero result is not misleadingly displayed as `0.0 mL`. |
| Incorrect dataset version | The app is intended to load the bundled v14 dataset. Confirm the actual asset path and the version metadata shown or used by the app. | Verify the bundled dataset version and test the behavior when the dataset cannot be loaded or its schema is unsupported. |
| CRI calculation uses hardcoded v15 values while v14 is active | The intended mitigation is to keep the existing CRI form UI but refuse calculation when the required data is unavailable in the active dataset. | Add or verify a widget test that taps Calculate and asserts that the unavailable-data message appears and no calculated result is shown. |
| CRI rate-unit conversion errors (`mcg/kg/min`) | CRI calculation is intended to remain unavailable until the required dataset information is present. Unit conversion should not be performed using unsupported or hardcoded values. | Before implementing CRI calculation, add unit tests for the required time and mass-unit conversions using assignment-approved test fixtures. |
| Incorrect interpretation of bag volume | The CRI calculation is not to proceed without the required data and a defined formula. | Before implementation, document whether the specified volume means initial or final bag volume and test the formula using assignment-provided examples. |
| Malformed or unavailable dataset JSON | `DrugDataService` contains dataset-loading and JSON-parsing logic. Confirm that failures are propagated to a clear user-visible error state. | Add or verify tests for malformed JSON, a missing asset, an invalid dataset structure, and an unsupported schema version. |
| Truncated or tampered dataset update | Secure dataset updates, including signature verification, have not been confirmed as implemented. | If required by the assignment, implement and test integrity/signature validation, truncated payload handling, and failure recovery before claiming this protection exists. |
| App is closed during a dataset update | Atomic dataset updates have not been confirmed as implemented. | If updates are implemented, add tests showing that interruption cannot leave a partially written dataset active. |
| Offline device retains outdated data | A device using a bundled v14 dataset cannot receive later corrections while offline. An update mechanism has not been confirmed as implemented. | Document this limitation. If online updates are required, test update and recovery behavior after connectivity returns. |
| Conflicting dataset versions published by a server | A server-side publishing and conflict-resolution system has not been confirmed as implemented. | If required, add integration tests for concurrent publication and the specified conflict response. |
| Duplicate calculation logs after retry | Persistent calculation logging and an upload endpoint have not been confirmed as implemented. | If logging and upload are required, test retry behavior and ensure duplicate submissions are handled according to the assignment requirements. |

## Known limitations

- The app currently uses the bundled v14 dataset, according to the current implementation plan. Confirm the asset and version metadata in the repository before submission.
- A device using v14 cannot automatically receive a later dataset correction unless an update mechanism is implemented and available.
- Server-driven dataset updates, signature verification, atomic update handling, and server-side publishing have not been confirmed as implemented.
- The CRI calculation should remain unavailable when the active dataset lacks the required CRI information. The screen must not produce a result using unsupported hardcoded values.
- Some failure cases in the table may still need dedicated tests. Do not treat a proposed test as evidence that the behavior has already been verified.

## Release decision

**Not suitable for clinical use.**

This project is an assignment demonstration using fictional data. The implementation and tests have not established clinical validity or suitability for real veterinary treatment decisions. Missing backend protections and any unverified failure cases must be addressed before claiming those protections are complete.
