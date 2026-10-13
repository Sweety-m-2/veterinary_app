# Vetifi Reference --- Flutter Assignment

## Overview

This project is a Flutter implementation for the Vetifi Technologies SDE
Intern assignment. It demonstrates an offline-first veterinary
drug-reference interface using the assignment's fictional dataset.

**Important:** All drug names and dose data are fictional and must not
be used for clinical decisions.

The current implementation focuses on the standard dose calculator and
CRI user interface. The bundled dataset is v14 (schema version 2). The
app validates required data and refuses calculations when required
information is missing, inconsistent, or unusable.

The CRI screen provides an interface for the required inputs, but the
CRI calculation is not implemented. The app must not substitute
hardcoded v15 values when the required CRI data is unavailable in the
bundled dataset.

## Repository structure

The assignment expects the following files and folders. Update this
section if the actual repository layout differs.

``` text
/
├── app/                 # Flutter application
├── server/              # Backend service (not implemented)
├── README.md
├── DECISIONS.md
├── BREAK_IT.md
└── AI_LOG.md
```

## Implemented functionality

The current app work includes:

-   Flutter application interface with Dose and CRI navigation.
-   Bundled dataset loading for offline use.
-   Dataset and drug data models.
-   Dataset parsing and schema-version validation.
-   Standard dose calculation using available drug, species, weight,
    dose, and concentration data.
-   Weight input and conversion support for kg and lb.
-   Validation and refusal behavior for unusable data.
-   A CRI form with inputs for species, weight, dose rate, fluid rate,
    and bag volume.
-   An unavailable-data message when the CRI calculation cannot safely
    proceed with the available dataset.

The app must not generate a dose or volume result from missing or
unusable data. For example, Benzaprol in v14 has a concentration of
`10%`, which the current calculator cannot interpret as an explicit
mg/mL concentration. The app therefore refuses to calculate using that
concentration.

## Architecture

### Flutter UI

The app provides the standard dose-calculator screen, CRI form, and
bottom navigation.

### Data layer

The bundled dataset is loaded locally so that the app can access its
available data without requiring a network request at calculation time.

### Domain and calculation logic

The dose-calculation logic validates the inputs and required drug data
before producing a result. Unusable concentrations, unsupported data, or
invalid dose information should result in a clear refusal rather than a
misleading number.

### Dataset

-   Bundled version: `v14`
-   Schema version: `2`
-   Source: fictional dataset provided in the assignment

### Backend

The backend dataset service is not implemented in this submission.

## Not completed and known gaps

### Part A --- Dose calculator

The dose-calculation workflow and validation are implemented. Further
verification against all supplied dirty-data cases and the required
result-presentation criteria is still necessary before claiming full
compliance with Part A.

### Part B --- Search

The 50,000 generated entries, typo-tolerant ranking, stale-query
protection, and real midrange Android performance measurements are not
completed or verified.

### Part C --- Constant rate infusion

The CRI interface is present, but the actual CRI calculation is not
implemented. The app must not produce a calculated CRI result from
hardcoded values when the required data is unavailable.

### Part D --- Dataset server

The backend service, database, publishing endpoints, withdrawal
endpoint, manifest and dataset endpoints, authentication, cryptographic
signing, concurrency control, idempotency, chaos mode, and real-database
integration tests are not implemented.

### Part E --- Dataset updates

Automatic manifest checks, signed update verification, hash
verification, delta application, atomic dataset updates, persistent
calculation logs, and log upload are not implemented or verified.

The app cannot receive server corrections through an update pipeline
that has not been implemented.

### Part F --- Written decisions

The design decisions and limitations are documented in `DECISIONS.md`.
Statements about implementation and verification should be kept
consistent with the actual code.

### Part G --- Code review

The three hypothetical functions supplied in the assignment are reviewed
in `DECISIONS.md`, including a corrected version of the most serious
function. These code-review examples are not claims that the functions
are part of the app.

### Part H --- Delivery

The final Android APK, video demonstration, and final repository checks
must be completed before submission if they have not already been done.

## Setup and running

### Requirements

-   A compatible stable Flutter SDK
-   Flutter dependencies declared in `pubspec.yaml`
-   An Android device or emulator for running the application

### Run the app

From the repository root:

``` bash
cd app
flutter pub get
flutter analyze
flutter test
flutter run
```

If you are already inside the `app` directory, do not run `cd app`
again.

### Build an Android APK

From the Flutter project directory (`app/`):

``` bash
flutter build apk --release
```

The expected APK output path is:

``` text
build/app/outputs/flutter-apk/app-release.apk
```

Confirm that the build succeeds and that the APK exists before sharing
it.

## Testing and verification

The latest reported test run completed with **63 tests passing**.

The latest reported `flutter analyze` run found no errors but reported
five warnings or informational notices:

-   One unused function.
-   Two deprecated form-field value usages.
-   Two `print()` statements in `tool/probe.dart`.

These results describe the reported run, not necessarily the final
submitted commit. Rerun both commands after any final changes and update
this section if the results differ.

Automated tests do not by themselves establish that all assignment
requirements or failure scenarios have been covered.

## Safety limitations

-   The dataset contains fictional assignment data and is not suitable
    for clinical use.
-   A calculation must be refused when required data is missing,
    inconsistent, unsupported, or unusable.
-   The current CRI interface does not perform the CRI calculation.
-   The backend and signed dataset-update pipeline are not implemented.
-   The app cannot automatically receive corrections from a server
    through the current implementation.
-   A device that remains offline can continue to use its bundled
    dataset, but that dataset may become outdated.
-   The current submission is an assignment implementation, not a
    clinically validated veterinary application.


