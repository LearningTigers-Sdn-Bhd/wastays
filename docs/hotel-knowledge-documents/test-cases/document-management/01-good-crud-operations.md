# Good: CRUD Operations

## Create Text Document
1. Admin navigates to Knowledge Documents page
2. Clicks "Add Document" and fills in title, selects category "FAQ" and source type "Text"
3. Enters content in the textarea and submits
4. Document is created with `embedding_status: "pending"`, no chunks yet
5. Redirected to index page with success notice

## Create PDF Document
1. Admin selects source type "PDF", the textarea hides and file upload appears
2. Uploads a valid PDF file and submits
3. Document is created with Active Storage attachment
4. `content` field remains null

## View Document Detail
1. Admin clicks a document title in the index table
2. Show page renders: content (or file link), chunks list, metadata panel
3. Metadata shows category, source, language, version, effective date, embed status, tags

## List Documents
1. Index page shows all documents with correct columns
2. Category pills, embedding status pills, and version badges display correctly
3. Mobile card layout renders when viewport is narrow

## Edit Document
1. Admin opens edit form for an existing document
2. Pre-filled values match the saved document
3. Changing source_type toggles between textarea and file upload
4. Submitting updates the document and redirects to index

## Delete Document
1. Admin clicks "Delete" from the manage dropdown
2. Confirmation dialog appears
3. On confirm, document is deleted along with its chunks and Active Storage attachment
