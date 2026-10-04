# Search

Search opens from the inbox and uses cached SwiftData metadata only. It covers sender/recipient names and addresses, subject, snippet, account name/email, label names, and attachment filenames. Multiple terms must all match, across any fields; quoted phrases match within one field. Matching ignores case, diacritics, and character width. Results retain newest-first ordering.

A disposable trigram index builds from value snapshots away from the main actor when cached metadata changes. Obsolete builds stop when the snapshot changes or search closes. Typing never calls Gmail, loads bodies, or rebuilds the index. One- and two-character terms scan normalized metadata. Search defaults to the selected inbox account, can switch to all accounts, and excludes Trash/Spam unless explicitly enabled. Sample mail is searchable when exploring without an account.

Filter chips narrow results to Unread, Starred and Attachments. Operators support from:, to: (including Cc/Bcc), subject:, label: (exact name or provider ID), before:, after:, has:attachment and is:read/unread/starred. before/after require YYYY-MM-DD local calendar dates; after includes that day, before excludes it. Incomplete syntax remains visible with an explanation. A fully quoted token such as "from:alex" searches for a literal phrase.

Recent searches retain up to ten submitted/opened queries; history can be cleared or disabled. Up to twenty named saved searches preserve the query, filters, Trash/Spam option and account. These use versioned local preferences; saved scopes whose account has been removed are hidden. They can be deleted from their context menu.

Search only covers downloaded mail; full bodies, provider search, and persisted full-text indexing remain future work. The existing database schema is unchanged. Unit tests cover matching, isolation, Unicode, operators, dates, saved searches, candidate verification, cache changes and Trash/Spam. UI tests cover sample and cached search, filters and no-results states. See the shared validation record in [feature-wave](../../docs/feature-wave.md).
