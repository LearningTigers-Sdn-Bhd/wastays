# Bad: Validation Errors

## Missing Required Fields
1. Admin submits form with blank title
2. Validation error: "Title can't be blank"
3. Form re-renders with error state, no redirect

## Invalid Category
1. Admin submits with category set to empty string
2. Validation error: "Category can't be blank" or "Category is not included in the list"

## Invalid Source Type
1. Admin submits with source type set to "markdown" or other invalid value
2. Validation error: "Source type is not included in the list"

## Missing Content for Text Source
1. Admin selects source type "Text" and submits without entering content
2. No validation error (content is optional — admins can create a document shell and fill later)

## Non-PDF Upload for PDF Source
1. Admin selects source type "PDF" and uploads a `.png` image
2. Accept attribute restricts to `application/pdf`, but client-side handling may vary
3. Server should validate content type on attachment

## Tags Overflow
1. Admin enters a very large number of comma-separated tags
2. PG array has no hard limit, but very long arrays may cause UI overflow
