# DECISIONS.md

## Scope and implementation status

The current submission focuses on **Part A: the offline dose calculator** and the **CRI user interface**. The CRI calculation, backend dataset service, signed updates, atomic update application, and calculation-log synchronization are not complete. The bundled dataset is fictional assignment data and must not be used for clinical decisions.

The answers below distinguish intended safety behavior from features that are not implemented.

# Part F — Written questions

## 1. Small doses

The app should preserve the full calculated value internally and apply rounding only when formatting the displayed result. For the 2.5 kg kitten example, the required volume is 0.07 mL. Displaying only 0.1 mL would lose meaningful precision. For the 40 kg dog example, 38.4 mL can be displayed as 38.4 mL.

The displayed volume must be prominent, include its unit, and appear alongside the calculated dose and concentration. The app should not round a value when doing so materially changes the result or makes a small positive value appear to be zero. It should also avoid implying that a displayed value can be measured accurately if the available measuring device cannot support that precision.

My implementation calculates the dose and volume and formats the result for display. The final formatter and tests must be checked to confirm the exact number of decimal places in the submitted build. I would not claim that every small-volume case is handled correctly until those cases are explicitly tested.

## 2. Missing species data

The strongest argument for showing another species' dose with a warning is that an experienced veterinarian might find the information useful as contextual reference material when species-specific data is missing. Hiding all related information could make the app less useful to an experienced user.

However, a warning can be overlooked, and a dose established for one species cannot automatically be assumed appropriate for another. Showing the other species' dose in the selected species' workflow also risks users misinterpreting it as a valid result.

My decision is that the app must not substitute a dog dose when cat data is missing or calculate a result using that fallback. It should clearly report that usable data is unavailable for the selected species and refuse the calculation. Missing, inconsistent, or unsupported data should fail safely rather than produce a plausible-looking number.

The implementation should be tested with missing species data, malformed dose ranges, and unusable concentrations to confirm that no result is produced.

## 3. Bag volume

Adding a drug to a fluid bag changes the final mixture volume unless an equal volume of fluid is removed. For example, adding 10 mL to a nominal 100 mL bag without removing fluid produces approximately 110 mL of total mixture. At a fluid rate of 10 mL/hour, 110 mL would take 11 hours to infuse, assuming the entire final mixture is delivered at that rate.

If 10 mL is removed first and the final mixture volume remains 100 mL, the same rate corresponds to 10 hours. The distinction matters when the calculation uses final mixture volume and the actual delivered fluid rate. It may not change a result based on a separately specified fixed duration or total delivered amount, depending on the defined calculation model.

My current implementation provides the CRI interface but does not calculate the amount to add or the bag duration because the CRI calculation is not implemented. The interface must not present an invented result. A future implementation needs an explicit volume convention and tests for both cases.

## 4. Users who never update

If a veterinarian remains offline for five months with v14 installed, the app cannot independently know that a newer Benzaprol concentration has been published. An offline app cannot retrieve a correction it has never received.

The app should continue using its bundled data offline, but it must validate that data before calculating. In this example, Benzaprol's `10%` concentration cannot be interpreted by my calculator as an explicit mg/mL concentration, so the app refuses the calculation and explains why. It must not guess a conversion or assume that v15 is installed.

The dataset version should remain visible so the user can identify which data is present. A future update mechanism could check for newer signed datasets whenever connectivity returns and apply verified updates safely.

My current submission does not implement the backend or automatic signed dataset updates. Therefore, I cannot claim that it delivers corrections to offline devices. A stale dataset remains a limitation until a valid update is received.

## 5. Leaked signing key

If the private signing key is leaked, an attacker could sign a malicious dataset or manifest that appears authentic to clients trusting that key. If the attacker can distribute the signed content to a client, that client may accept it unless additional validation rejects it.

Installed apps that trust only the compromised public key cannot distinguish legitimate signatures from an attacker's signatures made with the stolen private key. A device that remains offline will not receive a revocation or replacement key automatically.

A recovery design should support key rotation, for example by shipping a new trusted public key through a trusted app release or by using a carefully designed trust mechanism that allows an already trusted key to authorize a replacement. Recovery procedures must also account for a compromised key that can no longer be trusted.

My current submission does not implement signed updates or key rotation, so it cannot claim to recover from a leaked signing key without an app release. I would treat key protection, rotation, and recovery as required work before relying on a production update system.

## 6. Limits of my design

The bundled-dataset approach is useful for first launch and offline calculation because it avoids a network dependency during calculation. Its limitation is that a device can remain on an outdated dataset indefinitely if it never receives an update.

For example, a clinic could continue using v14 after a correction has been published. Local validation can reject data that is visibly unusable, such as Benzaprol's ambiguous concentration, but it cannot discover a correction that the device has never received.

For this assignment, I retain offline-first behavior and refuse calculations when required data is unusable. For a production app, I would add a signed dataset update mechanism with hash verification, atomic application, version tracking, and recovery after interrupted updates. The app would still calculate offline from its last verified dataset.

Those update and recovery features are not complete in my current submission. Therefore, the current implementation should not be treated as a production-ready clinical reference system.

# Part G — Code review

The following reviews concern the three hypothetical functions supplied in the assignment. They are not claims that these functions are implemented in my Flutter app.

## Function 1 — Dart `volumeMl`

### Problems ranked by potential harm

1. **Unvalidated concentration:** `double.parse` can throw on malformed input. More importantly, extracting the first token accepts a number without proving that the unit is mg/mL. A percentage such as `10%` must not be silently treated as `10 mg/mL`.
2. **Invalid or non-finite inputs:** Zero or negative concentration, negative or zero weight, negative dose, `NaN`, and infinity can cause invalid results or exceptions.
3. **Unvalidated units:** Every unit other than `lb` is treated as kg. A typo or unsupported unit therefore silently changes the calculation.
4. **Unnecessary precision loss:** Rounding to one decimal place can turn a small positive volume into `0.0 mL` or substantially change the displayed result.
5. **Conversion constant:** Using `2.2` as the pounds-per-kilogram conversion introduces approximation error; use a documented conversion constant consistently.

### Corrected version

This example accepts only an explicit `mg/mL` concentration and rejects invalid inputs. It returns the unrounded value; display formatting should be handled separately.

```dart
double volumeMl(
  double weight,
  String unit,
  double dosePerKg,
  String concentration,
) {
  if (!weight.isFinite || weight <= 0) {
    throw ArgumentError('Weight must be positive and finite.');
  }

  if (!dosePerKg.isFinite || dosePerKg <= 0) {
    throw ArgumentError('Dose must be positive and finite.');
  }

  final normalizedUnit = unit.trim().toLowerCase();

  final kg = switch (normalizedUnit) {
    'kg' => weight,
    'lb' => weight / 2.2046226218,
    _ => throw ArgumentError('Unsupported weight unit.'),
  };

  final match = RegExp(
    r'^\s*(\d+(?:\.\d+)?)\s*mg/mL\s*$',
    caseSensitive: false,
  ).firstMatch(concentration);

  if (match == null) {
    throw ArgumentError(
      'Concentration must be explicitly specified in mg/mL.',
    );
  }

  final mgPerMl = double.parse(match.group(1)!);

  if (!mgPerMl.isFinite || mgPerMl <= 0) {
    throw ArgumentError('Concentration must be positive and finite.');
  }

  final result = (kg * dosePerKg) / mgPerMl;

  if (!result.isFinite || result <= 0) {
    throw ArgumentError('Calculated volume is invalid.');
  }

  return result;
}
```

This function illustrates input validation and separation of calculation from display formatting. A production implementation should also validate supported dose units and use a tested concentration parser.

## Function 2 — Dart `applyUpdate`

### Problems ranked by potential harm

1. **Deletes existing data before validating the update.** If JSON parsing or an insertion fails, the existing dataset may already have been destroyed.
2. **No signature or hash verification.** The function does not establish that the downloaded payload is authentic and intact.
3. **Does not validate the complete payload.** It does not check schema version, base version, dataset version, entries, or malformed fields before changing data.
4. **Treats upserts as the entire dataset.** A delta containing only changed entries must not replace every existing drug.
5. **No atomic transaction is shown.** A failure midway through the inserts could leave incomplete data.
6. **Version is written after the data changes without a demonstrated atomic guarantee.** Data and version could become inconsistent if the process stops unexpectedly.

### Corrected approach

I would validate the downloaded payload and verify its signature and hash before changing the database. I would confirm the expected base version, distinguish a full snapshot from a delta, and validate every entry using the same rules as the calculator. Then I would apply all data changes and the version update inside one database transaction, rolling back on failure. For stronger recovery guarantees, I would use a tested transactional storage design or build a complete replacement snapshot and atomically switch to it.

The current submission does not implement this complete signed, atomic update mechanism.

## Function 3 — Python FastAPI `publish`

### Problems ranked by potential harm

1. **No dataset validation or cryptographic signing.** Invalid or altered drug data could be published without the required safeguards.
2. **SQL injection risk.** The payload is interpolated directly into SQL instead of using parameterized queries.
3. **No concurrency control.** Two administrators can read the same latest version and race to publish conflicting versions.
4. **No immutable-version or base-version checks.** The function does not verify the requested base version or safely reject conflicting publication attempts.
5. **Weak authentication design.** A single environment key comparison is the only shown authorization mechanism; there is no rate limiting or audit trail.
6. **No idempotency support.** Retrying a request after a network failure can produce a different outcome rather than returning the original result.
7. **Fragile version parsing and error handling.** The code assumes a particular version format and does not show transaction handling or structured validation errors.

### Corrected approach

I would validate the schema and every entry before publication, use parameterized SQL, and perform version checks and insertion in a database transaction. A uniqueness constraint and optimistic concurrency check against the requested base version should ensure that only one competing publication succeeds; the other should receive `409 Conflict`. I would store immutable published payloads, use idempotency keys for retry safety, and sign the published manifest and payload with a protected private key. Admin authentication, audit logging, and structured errors would also be required.

The backend publication service is not implemented in my current submission, so these are design corrections rather than implemented protections.

# Final verification status

- **Implemented:** Offline bundled dataset loading and dose-calculator validation/refusal behavior; CRI interface.
- **Not implemented:** Full CRI calculation; backend dataset publishing service; signed dataset updates; atomic update application; calculation-log upload.
- **Testing:** The latest reported `flutter test` run passed 63 tests. The latest reported `flutter analyze` run found no errors but reported five warnings/information notices. These results should be rerun against the final commit.
- **Release decision:** This is an assignment implementation using fictional data, not a clinically validated veterinary application. I would not release it for clinical use until the outstanding functionality, validation, update security, and testing work is complete.
