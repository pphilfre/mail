# Dispatch visual system

The concept is a quiet correspondence desk: warm paper, ink, and a restrained plum accent. New York headings give the workspace an editorial character; SF Pro keeps the correspondence and controls familiar. Content remains opaque. Depth comes from native navigation, tabs, and transient controls.

## Shared rules

| Role | Light | Dark |
| --- | --- | --- |
| Reading paper | `#FAF9F6` | `#211F23` |
| Workspace canvas | `#F1EFEB` | `#19181B` |
| Primary ink | `#252428` | `#F2EFF1` |
| Secondary ink | `#666269` | `#B8B2BC` |
| Plum accent | `#705267` | `#D2B5C9` |
| Divider | `#DEDAD7` | `#423E45` |

- Colours use dynamic UIKit providers, including stronger dividers for Increase Contrast. Primary text, secondary text and the accent each exceed 4.5:1 contrast on their reading surface in both appearances.
- Headings use system New York at semantic title sizes. Sender names use SF Pro subheadline with medium or semibold weight; subjects use body; previews use subheadline; dates and metadata use caption or footnote. Text follows Dynamic Type.
- Use 20-point outer insets and a spacing scale of 4, 6, 8, 12, 16 and 24 points. Normal inbox rows have 14-point vertical padding; compact rows have 6. Reader and composer columns have a maximum width of 680 points including their insets. Plain message bodies have 6-point line spacing.
- Use continuous opaque paper surfaces and fine dividers. Navigation sections are grouped by space. Counts are plain text; sender icons are neutral. The 10-point corner radius is reserved for small identity surfaces and auxiliary controls.
- Unread state combines a small plum dot, font weight and a spoken value. Selected text filters have an underline and a selected accessibility trait. Account colours survive as small identity markers in mixed-account results; warning and error colours retain their meanings.
- Icons on custom controls use a shared 19-point medium weight and at least a 44-point touch target. Text, rather than icon scale, follows the user's reading size. Sender, subject, preview and recipient text wrap at accessibility sizes; dates move below the sender at those sizes. The inbox mailbox picker becomes a native menu at accessibility sizes.
- Native bars, tabs and search retain their system treatment. Custom reader and composer docks, the More control and confirmations use system Liquid Glass with an opaque fallback for Reduce Transparency. Glass never covers the email body itself.
- Transitions use a 0.2-second ease-in-out curve and respect Reduce Motion. Confirmation feedback keeps its existing timing, haptics and Undo behavior, with no confetti, spinning icons or spring bounce.

## Screen application

- **Inbox:** editorial mailbox title, a quiet account scope, native mailbox selector and underlined filters above a continuous message list. Real mail, sample mail and search share the same message-row component.
- **Mailboxes:** aligned single-column navigation with neutral icons, plain counts and a checkmark for selection. Account, label, smart-folder and utility actions remain available.
- **Reader:** New York subject, separated sender metadata, comfortable column width and plain text rhythm. HTML has adaptive fallback ink and underlined plum links; sender-provided layouts, image permissions and the security policy are retained. Conversation messages use rules and space instead of enclosing cards.
- **Search:** native focused search field, shared filters, the same inbox rows, sentence-case section headings and consistent insets. Query, scope, saved history and search behavior are retained.
- **Compose:** aligned recipient and sender labels, wrapping subject, a spacious native rich-text editor, understated attachment rows and a glass editing dock. Rich-text formatting, recipients, signatures, autosave and sending remain intact. Editor paragraph spacing is display styling; it is not added to the outgoing rich-text document.
- **Settings:** a continuous paper list with sentence-case groups and familiar native toggles and pickers. Preferences and storage keys are retained.
- Welcome and transient confirmations follow the same colours, typography and motion rules.

## Validation

- Local Swift parser: all 21 edited Swift files passed. This checks syntax, not SDK availability, type checking or execution.
- Calculated contrast on paper: light primary **14.65:1**, secondary **5.67:1**, accent **6.45:1**; dark primary **14.31:1**, secondary **7.89:1**, accent **8.71:1**.
- `git diff --check` passed.
- The whole-project supplementary parser reports errors in existing, untouched files, including conditional-compilation and trailing-closure constructs. These are outside this change; no claim is made about their compilation status.
- This Windows workspace has no Xcode or iOS simulator. An iOS build, unit/UI tests and rendered visual review remain unverified. Use the existing macOS build/test workflow and review inbox, mailbox panel, reader, search, compose and settings on iPhone and iPad in light/dark appearance, accessibility text sizes, VoiceOver, Increase Contrast, Reduce Transparency and Reduce Motion. Existing UI tests already exercise inbox density, filters, drafts, composing, search, reader actions and dark appearance with large text.

The implementation builds on the current working tree; pre-existing changes were retained. Mail models, storage, provider logic and search algorithms were not changed by this visual pass.

System behavior references: [Apple typography](https://developer.apple.com/documentation/technologyoverviews/fonts), [Reduce Transparency](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityReduceTransparency), and [SwiftUI Liquid Glass](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)).
