# Admin CRUD & UI

## Controllers (3 separate)

The unified Knowledge Documents CRUD was split into 3 category-scoped controllers:

| Controller | Path | Scope |
|---|---|---|
| `KnowledgePoliciesController` | `app/controllers/hotel_portal/knowledge_policies_controller.rb` | `where(category: "policy")` |
| `KnowledgeFaqsController` | `app/controllers/hotel_portal/knowledge_faqs_controller.rb` | `where(category: "faq")` |
| `KnowledgeGeneralInfosController` | `app/controllers/hotel_portal/knowledge_general_infos_controller.rb` | `where(category: "general_info")` |

Each controller exposes standard RESTful CRUD (index, show, new, create, edit, update, destroy) scoped to `current_hotel` and its category. Key differences from the original single controller:

- `index` filters by `where(category: "policy")` (or faq / general_info)
- `set_document` scopes to the category: `@hotel.knowledge_documents.where(category: "policy").find(params[:id])`
- `new` auto-sets category: `.build(category: "policy")`
- `create` merges category: `.build(document_params.merge(category: "policy"))`
- `document_params` no longer permits `:category` — it's inferred from the controller

Each controller defines path helpers for shared views:

| Helper | Purpose |
|---|---|
| `kb_index_path` | Index URL (category-specific) |
| `kb_show_path(doc)` | Show/update/destroy URL |
| `kb_edit_path(doc)` | Edit form URL |
| `kb_new_path` | New form URL |

### Strong Parameters

```ruby
params.require(:hotel_knowledge_document).permit(
  :title, :source_type, :language,
  :effective_date, :content, :file, :metadata,
  tags: []
)
```

Note: `:category` is intentionally excluded — it is auto-set by the controller on create.

## Views

### Shared index partial (`_documents_table.html.erb`)

**Path:** `app/views/hotel_portal/knowledge_base/_documents_table.html.erb`

The 3 per-category index pages are thin wrappers that render this shared partial with category-specific locals (title, subtitle, button text, empty-state messages).

The desktop layout uses a **div-based CSS grid** (replacing the original HTML `<table>`) to avoid dropdown clipping and cell-wrapping issues. Column widths are fixed via `grid-template-columns`:

| Column | Width | Notes |
|--------|-------|-------|
| Expand | `40px` | Chevron toggle |
| Title | `minmax(0, 1fr)` | Icon + title with `truncate` |
| Source | `110px` | `text` / `pdf` badge |
| Tags | `180px` | Max 3 pills + `+N` overflow |
| Effective | `130px` | Date or "Forever" |
| Status | `120px` | Color-coded embedding pill |
| Updated | `150px` | `time_ago_in_words` |
| Action | `120px` | "Manage" dropdown |

Each document row is a `<div data-controller="knowledge-row-expand">` containing:
1. A **summary grid row** — clickable, toggles expansion
2. An **expandable content div** (hidden by default) — shows:
   - **Text documents** — full content in a scrollable `<pre>` block
   - **FAQ documents** — Q&A pairs rendered from `metadata.qa_pairs`
   - **PDF documents** — filename + "Open PDF" button (new tab)

**Mobile layout:** Collapsible cards (`lg:hidden`) with the same expand/collapse behavior, showing summary metadata in a definition list and content below.

**Empty state:** Icon + heading + description + "Add" call-to-action button.

The card wrapper omits `overflow-hidden` so the absolute-positioned dropdown menu can extend outside the card boundary without clipping.

### Shared form (`_form.html.erb`)

**Path:** `app/views/hotel_portal/knowledge_base/_form.html.erb`

Common fields: title, source_type (select), language, effective_date, tags. No category selector (auto-set by controller).

Conditional fields toggled via Stimulus:
- `source_type: "text"` → shows textarea for `content`
- `source_type: "pdf"` → shows file upload for `file`, hides textarea
- Shows current file name if document already has an attachment

### Shared New / Edit (`new.html.erb` / `edit.html.erb`)

**Path:** `app/views/hotel_portal/knowledge_base/new.html.erb`
**Path:** `app/views/hotel_portal/knowledge_base/edit.html.erb`

Centered layout (max-w-2xl), back link, renders `_form` from `knowledge_base/`.

### Shared Show (`show.html.erb`)

**Path:** `app/views/hotel_portal/knowledge_base/show.html.erb`

Full-width layout (max-w-1600px):
- Left column: content preview (text or file link), chunks list
- Right column: metadata panel (category, source, language, version, effective date, embedding status, tags, timestamps)

## Stimulus Controllers

### `knowledge_document_controller.js`

**Path:** `app/javascript/controllers/knowledge_document_controller.js`

Toggles between textarea and file upload based on `source_type` select value:

```javascript
export default class extends Controller {
  static targets = ["sourceType", "textContent", "pdfUpload"]

  toggleSourceType() {
    if (this.sourceTypeTarget.value === "pdf") {
      this.textContentTarget.classList.add("hidden")
      this.pdfUploadTarget.classList.remove("hidden")
    } else {
      this.textContentTarget.classList.remove("hidden")
      this.pdfUploadTarget.classList.add("hidden")
    }
  }
}
```

### `knowledge_row_expand_controller.js`

**Path:** `app/javascript/controllers/knowledge_row_expand_controller.js`

Toggles expand/collapse on row click in the index table. Ignores clicks inside dropdowns, links, and buttons (stops propagation).

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["expandable", "chevron"]

  toggle(event) {
    if (event.target.closest("a, button, [data-controller='dropdown']")) {
      return
    }
    this.expandableTarget.classList.toggle("hidden")
    this.element.classList.toggle("is-expanded")
    if (this.hasChevronTarget) {
      this.chevronTarget.classList.toggle("rotate-180")
    }
  }
}
```

**Behavior:**
- Clicking anywhere on the summary row toggles the expandable content sibling
- Clicks on the Manage button, action links, or dropdown items are ignored (the existing `dropdown_controller.js` already stops propagation, but this controller also guards against `a`, `button`, and `[data-controller='dropdown']` targets)
- The chevron SVG rotates 180 degrees when expanded (using CSS transition)
- Multiple rows can be expanded simultaneously (no accordion constraint)

## Routes

```ruby
resources :knowledge_policies
resources :knowledge_faqs
resources :knowledge_general_infos
```

Nested under the hotel portal scope, generating:

| Route Helper | Path | Controller#Action |
|---|---|---|
| `hotel_knowledge_policies_path` | `/hotel/:id/knowledge_policies` | `knowledge_policies#index` |
| `new_hotel_knowledge_policy_path` | `/hotel/:id/knowledge_policies/new` | `knowledge_policies#new` |
| `edit_hotel_knowledge_policy_path` | `/hotel/:id/knowledge_policies/:id/edit` | `knowledge_policies#edit` |
| `hotel_knowledge_policy_path` | `/hotel/:id/knowledge_policies/:id` | `knowledge_policies#show/update/destroy` |

Same pattern for `knowledge_faqs` and `knowledge_general_infos`.

Diagnostics add staff-only routes under the same hotel portal scope:

| Route Helper | Path | Controller#Action |
|---|---|---|
| `hotel_knowledge_diagnostics_path` | `/hotel/:id/knowledge_diagnostics` | `knowledge_diagnostics#index` |
| `hotel_knowledge_diagnostic_path` | `/hotel/:id/knowledge_diagnostics/:id` | `knowledge_diagnostics#update` |

`KnowledgeDiagnosticsController` authorizes through `HotelPolicy#update?`, matching the document management pages.

## Navigation

- **Sidebar** — The flat "Knowledge Documents" link in Property section was replaced with an expandable "Knowledge" section (using the same `<details>` pattern as Reports), containing 4 children:
  1. Policy Management → `hotel_knowledge_policies_path`
  2. FAQs Management → `hotel_knowledge_faqs_path`
  3. General Info → `hotel_knowledge_general_infos_path`
  4. Knowledge Diagnostics → `hotel_knowledge_diagnostics_path`
- **Global search** — Updated with 3 separate entries, one for each resource page

## Knowledge Diagnostics UI

The diagnostics index is an operational review queue for weak or unanswered knowledge turns.

- Summary counts show open, unavailable/weak, reviewed, and resolved diagnostics.
- Filters support status, answer mode, suggested category, and date range.
- Each row shows the guest question, intent/topic, answer mode, suggested category, best match/document, created time, and current status.
- Expanded row details include generated answer, matched chunk/document/category/distance data, searched and fallback categories, and status action buttons.
- Staff can mark a diagnostic as reviewed, resolved, or dismissed.
