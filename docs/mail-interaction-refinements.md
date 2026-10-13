# Dispatch interaction refinements

This pass keeps the established paper and plum visual system while removing competing controls and making the active action easier to recognise. Paper #FAF9F6, canvas #F1EFEB, ink #252428, plum #705267 and violet #614CC4 supply the light palette; the existing adaptive dark equivalents remain. Serif navigation and reader titles anchor the interface, while system text stays legible in forms and lists. All controls retain 44-point touch targets.

## Navigation and layout

- Inbox search uses the Search tab. The redundant account text and draft shortcut are removed. A compact account dropdown sits beside the mailbox menu, with account management inside it. Toolbar widths balance Inbox and New message titles. Drafts remain in their own mailbox with the device/Gmail switch.
- The mailbox panel uses compact 44-point rows and smaller section gaps. Accounts and Settings remain pinned to its bottom edge instead of requiring a scroll.
- Older-message loading uses the same neutral surface and plum accent as the rest of the inbox, with an explicit loading state.
- Search keeps filters and scope above results. Filter status and result count share a single row. Its distinct bordered input sits above the keyboard. Close and swipe retain their existing navigation semantics.
- Accounts now opens with an account directory. Each account leads to its identity, preferences, queue and connection controls. Unsupported providers no longer occupy rows among live actions.
- Tasks opens directly onto grouped next steps, with pinned status filters and a coloured plus button above the bottom Search control. New tasks focus their title immediately; dates, priority and list details are optional disclosures.
- Notifications have an opaque hit surface and dismiss on tap. Undo and dismiss controls retain their own actions. Empty parts of reader and composer control pills consume touches.

## Reader and intelligence

- Share and reader controls use matching icon sizes and touch targets. Message action rows use fixed icon columns and matching insets for buttons, menus and navigation links.
- Opening an email runs local inspection of downloaded content, including sender, links, embedded QR images and cached attachments. The shield displays progress, then the existing neutral/green/amber/red risk status. Missing verification remains neutral; original-message DNS verification and reputation lookups remain explicit inspector actions.
- Sender logos use a uniform rounded box. Lookup starts at the registrable root, then tries alternate raster formats, sender subdomains, www and declared same-site icon paths. Bounds, decode validation, shared requests and caches remain in place; no third-party logo service is used. Websites without a usable supported icon still display the category fallback.
- Summarise has a violet action surface and an icon to cancel. Its prompt includes the mailbox owner and asks for their essential update, deadline or next action in one or two short sentences. A brief over 80 words is compressed once, then rejected if still too long.
- Writing assistance opens a compact horizontal options bar without headings, descriptions or an automatic rewrite. Shorten targets 40–60% of the original words; Expand targets 140–175%. Superficial length changes are retried once and then shown as an error. Choosing a tool shows its revision directly in the draft, with green additions and red struck-through deletions. Apply changes and Keep original remain beside that preview. Applying keeps the existing range, stale-draft guard, formatting outside that range and Undo support. Suggestions remain uncommitted until accepted.

## Receipts

- Detection distinguishes a merchant purchase from a person-to-person transfer, incoming payment, confirmed refund and unpaid invoice. Unclear directions remain unconfirmed instead of becoming spending.
- Incoming amounts have a green plus; outgoing amounts have a red minus. Direction can be corrected in Review and is included in CSV exports. Optional direction fields preserve older saved corrections.
- Receipt details show extracted order/transaction references, item, quantity, payment method, tax, delivery and other labelled facts where present. Nothing is invented when a field is missing.
- The wallet overview focuses on money-in/out totals and six-month cash-flow charts. Explanatory paragraphs and the redundant transaction count are removed; the month filter is in the toolbar. Merchant detail includes its own activity chart. Each currency is kept separate, and unknown amounts or directions are excluded. Dates reflect when the email was received; charts cover downloaded mail, not a complete bank statement.

## Validation

32 edited/new Swift files passed the supplementary Windows syntax check; CI partition and cache guards passed for all 33 UI tests. Whitespace checks passed. Ten new unit regressions cover transfer versus purchase, incoming payments/refunds/invoices, separate-line totals, per-currency charts, old correction decoding, substantive writing lengths, Unicode/repeated-word diffs, icon discovery and summary owner context. Existing UI checks were updated for the new navigation, drawer and search-field locations.

Xcode compilation, XCTest and device packaging run on macOS GitHub Actions. The full iOS CI workflow is dispatched for the committed snapshot and produces an unsigned IPA after validation. Build results and simulator screenshots are pending; no passing Xcode build or on-device model-quality result is claimed at submission.

## Failure review and follow-up

Run 38467005455 compiled successfully and passed all 188 unit tests. It passed 20 of 33 UI tests; 13 failed across the three test groups, preventing IPA packaging.

Five draft checks still targeted the removed inbox shortcut, and one Accounts check expected the old empty-state wording. Those checks now use the real Drafts mailbox and account screen. Task-status, task-details and search-field identifiers were being inherited from parent views, replacing the controls' own identifiers. Status buttons now have individual identifiers, optional task fields use an explicit disclosure button without identifier inheritance, and the search-list identifier is scoped before its inset controls. Picker checks accept their current accessibility type.

Simulator screenshots confirmed that the expanded cash-flow introduction pushed the receipt partly under the native search control, and the old writing drawer clipped options at large text sizes. The wallet now shows its graph/totals directly, receipt selection uses an explicit button/destination, and writing assistance is a horizontal strip with individually named options. Selecting a tool opens the coloured revision inline in the draft. The sending-account picker is constrained to one line so long addresses cannot overlap the subject/body at large text sizes.

All failure selectors were reviewed against logs and simulator evidence. Local syntax, whitespace and CI coverage checks are rerun for this correction. A fresh full macOS build/test/IPA run is submitted without waiting for completion, as requested; the correction is not yet claimed to pass XCTest.
