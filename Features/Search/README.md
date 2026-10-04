# Search

Search opens from the inbox toolbar and uses cached SwiftData metadata only. It covers sender/recipient names and addresses, subject, snippet, account name/email, label names, and attachment filenames. Multiple whitespace-separated terms must all match, across any fields; matching ignores case, diacritics, and character width. Results retain newest-first ordering.

A disposable trigram index builds from value snapshots away from the main actor when cached metadata changes. Obsolete builds stop when the snapshot changes or search closes. Typing never calls Gmail, loads bodies, or rebuilds the index. One- and two-character terms scan normalized metadata. Search defaults to the selected inbox account, can switch to all accounts, and excludes Trash/Spam unless explicitly enabled. Sample mail is searchable when exploring without an account.

Search only covers downloaded mail; full bodies, provider search, advanced operators, and persisted full-text indexing are future work. The existing database schema is unchanged. Unit tests cover field matching, account isolation, Unicode, short terms, candidate verification, metadata replacement, and Trash/Spam. UI tests exercise sample search and no-results presentation. macOS build/test verification is required before marking Stage 8 complete.
