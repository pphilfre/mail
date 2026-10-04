# Local search implementation

The first audit improvement adds a native search destination to the inbox. Search runs over cached metadata and works without connectivity; typing does not contact a provider.

- Matches sender and recipients, subject, snippet, account, label names, and attachment filenames.
- Uses an in-memory substring index, rebuilt from cached value snapshots away from the main actor.
- Supports multiple terms, case/diacritic/width-insensitive matching, and one- or two-character queries.
- Defaults to the selected account; supports all-account searches and explicit Trash/Spam inclusion.
- Includes sample-mode search, an empty prompt, result counts, and no-results presentation.
- Leaves the SwiftData schema unchanged. Search covers downloaded metadata, not the full remote mailbox or full message bodies.

Validation: five focused search unit tests and a search UI flow were added. macOS CI is pending; this stage is not yet marked complete. Existing signed-device Gmail checks remain outstanding.

After this stage passes its build/test gate, continue with draft safety and the remaining audit improvements.
