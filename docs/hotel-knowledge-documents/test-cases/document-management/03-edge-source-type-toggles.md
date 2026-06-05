# Edge: Source Type Toggles

## Switching Source Type Mid-Form
1. Admin selects "Text", enters content, then switches to "PDF"
2. Textarea hides, file upload appears
3. Switching back to "Text" shows the previously entered content still intact

## Editing Existing Document — Source Type Change
1. Document was created as "text" with content
2. Admin edits and changes to "PDF" — existing content field is ignored, file upload appears
3. Admin saves without uploading a file — document is updated with no content and no attachment
4. This is valid behavior (content and file are optional fields)

## Editing Existing Document — File Replacement
1. Document was created as "PDF" with an attached file
2. Admin edits and uploads a new file
3. Active Storage replaces the old attachment
4. Old attachment is purged via Active Storage cleanup

## Very Long Content
1. Admin pastes 100,000+ characters into the textarea
2. Form submits without truncation or error (DB text column handles this)
3. Show page renders the full content in a scrollable `<pre>` block

## UTF-8 and Special Characters
1. Content includes emoji, Chinese characters, or markdown formatting
2. Content is stored and displayed correctly without encoding issues
3. Tags with special characters (spaces, hyphens) are preserved

## Tags with Commas
1. Admin enters `tag1, "tag, with comma", tag3` in the tags field
2. The current implementation splits on comma — this would incorrectly split "tag, with comma"
3. Consider quoting support or alternative delimiter for future improvement
