# Agent Instructions for hinata_go (Flutter Project)

Welcome! You are an autonomous AI agent operating within the `hinata_go` repository. This file provides the essential context, commands, and architectural guidelines you must follow to ensure your contributions align with the project's high standards.

---

## 1. Project Overview & Domain

`hinata_go` is a Flutter application serving as an NFC card reader and management tool. It interacts with various arcade and transit card types (such as Felica, Aime, Banapass, AIC, ISO15693, and ISO14443A) using `flutter_nfc_kit`. 
The application manages card data, remote instances, scan logs, and user settings. It heavily utilizes modern Flutter paradigms including Riverpod for state management, GoRouter for navigation, and Material 3 with dynamic coloring for the UI.

---

## 2. Environment & Core Commands

### Prerequisites
- **Flutter SDK**: `^3.11.0`
- **Dart SDK**: Compatible with Flutter 3.11+
- **Platform Targets**: Android, iOS, Web, macOS, Windows, Linux

### Build & Run
- **Install Dependencies**: `flutter pub get`
- **Run App (Debug)**: `flutter run`
- **Build Android APK**: `flutter build apk`
- **Build iOS**: `flutter build ios`

### Linting & Formatting (Mandatory)
You MUST ensure your code complies with the project's linting rules defined in `analysis_options.yaml` (which extends `flutter_lints`).
- **Format Code**: `dart format .` (Run this prior to finalizing any task)
- **Static Analysis**: `flutter analyze` (Zero errors or warnings are expected. Do not proceed until the analyzer passes)

### Testing Strategies
The `test/` directory mirrors the `lib/` directory.
- **Run All Tests**: `flutter test`
- **Run a Single Test File**: `flutter test test/path/to/specific_test.dart`
- **Run Tests by Name**: `flutter test --plain-name "should return valid ScannedCard"`
- **Update Golden Files**: `flutter test --update-goldens`

---

## 3. Directory Structure

- `lib/constants/`: App-wide constants, keys (e.g., MIFARE keys), and static configurations.
- `lib/models/`: Pure Dart data classes (e.g., `ICCard`, `ScannedCard`, `RemoteInstance`). Contains `fromJson` and `toJson` methods.
- `lib/providers/`: Riverpod state management. Contains `Notifier` classes.
- `lib/services/`: Stateless service classes for external interactions (e.g., `NfcService`, API clients).
- `lib/ui/` or `lib/screens/`: Flutter widgets and pages.
- `lib/utils/`: Helper functions and parsers (e.g., Hex converters).
- `lib/navigation/`: GoRouter configuration.
- `lib/l10n/`: Localization files and delegates.

---

## 4. Architecture & State Management

### Riverpod (`hooks_riverpod`)
We strictly use **Riverpod** for dependency injection and state management.
- **Providers**: Prefer `NotifierProvider` over `StateNotifierProvider` as per modern Riverpod standards.
- **Widgets**: Extend `ConsumerWidget` or `HookConsumerWidget`. Do not use `StatefulWidget` unless managing complex, localized animation state.
- **Reading State**: 
  - Reactive listening: `final state = ref.watch(myProvider);` inside the `build()` method.
  - One-time read (callbacks): `final state = ref.read(myProvider);`
  - Mutating state: `ref.read(myProvider.notifier).updateState(newValue);`
- **Business Logic**: Keep UI components dumb. Place business logic inside the `Notifier` classes in the `lib/providers/` directory.

### Routing (`go_router`)
Navigation is declarative and handled by `go_router`.
- Define routes centrally in `lib/navigation/router.dart`.
- Navigate using `context.go('/path')` (for changing URL/deep-linking) or `context.push('/path')` (for stacking pages).

---

## 5. Code Style & Conventions

### Naming Conventions
- **Classes, Enums, Typedefs**: `PascalCase` (e.g., `ScannedCard`, `InstancesNotifier`).
- **Variables, Functions, Methods**: `camelCase` (e.g., `addInstance`, `updateInstance`).
- **Files and Directories**: `snake_case` (e.g., `app_state_provider.dart`, `nfc_service.dart`).
- **Constants**: `lowerCamelCase` or `SCREAMING_SNAKE_CASE` (prefer `lowerCamelCase` for Dart).

### Imports
Organize imports strictly in this order, separated by blank lines:
1. `dart:` core libraries (e.g., `dart:typed_data`, `dart:developer`).
2. Flutter framework imports (`package:flutter/...`).
3. External packages (`package:hooks_riverpod/...`, `package:go_router/...`).
4. Project-specific absolute imports (`package:hinata_go/...`).
5. Relative imports (e.g., `../models/card.dart`).

### Types & Null Safety
- Dart is strongly typed and null-safe. 
- **NEVER** suppress type errors with `dynamic` or use `as any` equivalents unless absolutely necessary (e.g., parsing untyped JSON maps).
- Use proper nullable types (`String?`, `ScannedCard?`) and handle null cases explicitly with `??` or early returns.

### Error Handling
- Use `try/catch` blocks for all asynchronous operations, particularly NFC reading (`NfcService`) and HTTP requests.
- Log errors using `dart:developer`'s `log(message, error: e, stackTrace: s)` function instead of `print()` for debugging.
- Surface errors gracefully to the UI, allowing the user to retry failed operations.

### UI & Styling
- The app uses **Material Design 3** alongside `dynamic_color`.
- Avoid hardcoding colors. Use `Theme.of(context).colorScheme` (e.g., `colorScheme.primary`).
- Avoid hardcoding text styles. Use `Theme.of(context).textTheme`.
- Break down large `build()` methods into smaller, reusable, stateless widgets rather than helper methods returning `Widget`.

---

## 6. Domain-Specific Guidelines (NFC)
- **Encapsulation**: Raw byte manipulation (e.g., `Uint8List`) should occur inside `lib/services/nfc_service.dart` or specific model parsers. The UI should only ever deal with parsed models like `ICCard` or `ScannedCard`.
- **Hex Formatting**: When displaying card IDs, use uppercase hex strings. Utilize the `convert` package or custom `toHex` utilities.

---

## 7. AI Agent Execution Rules
1. **Explore First**: Before writing code, use AST-grep or workspace symbol search to understand how similar features are implemented. Do not reinvent patterns.
2. **Atomic Changes**: Keep your changes focused. Do not refactor unrelated files while fixing a bug or adding a feature.
3. **Verification**: You MUST run `flutter analyze` after completing your code edits. If it fails, fix the errors before concluding your task.
4. **No Placeholders**: Write complete, production-ready code. Do not leave `// TODO: implement` or `// ... existing code` blocks in your final file writes.