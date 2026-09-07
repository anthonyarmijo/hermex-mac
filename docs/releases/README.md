# Mac release notes

Each Mac release has curated, user-facing notes committed with the release
candidate. The release workflow reads the file from the tag, prepends the common
download instructions, and appends GitHub's generated PR list for traceability.

## Preparing a release

1. Copy `TEMPLATE.md` to `mac-vX.Y.Z.md` using the exact intended tag name.
2. Compare the release candidate with the previous `mac-vX.Y.Z` tag.
3. Review every included PR body, linked issue, and commit. PR titles alone often
   hide the changes collected by a release-promotion PR.
4. Describe observable user benefits and fixes in plain language. Omit internal
   implementation details unless they affect compatibility, security, or use.
5. State known issues explicitly. Use `None known.` only after checking.
6. Remove every `REPLACE` marker and have the maintainer review the rendered
   Markdown before creating the tag.

The workflow rejects a tag whose matching file is missing, empty, still contains
a `REPLACE` marker, or omits the required `Highlights` and `Known issues`
sections, or leaves either required section empty. Generated releases remain
drafts until the maintainer verifies the artifact and notes.
