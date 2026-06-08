# Models and Schema

## `hotel_knowledge_documents`

```ruby
class HotelKnowledgeDocument < ApplicationRecord
  belongs_to :hotel
  has_many :chunks, class_name: "HotelKnowledgeChunk", dependent: :destroy
  has_one_attached :file

  validates :title, :source_type, :category, presence: true
  validates :source_type, inclusion: { in: %w[text pdf] }
  validates :category, inclusion: { in: %w[policy faq general_info] }
  validates :embedding_status, inclusion: { in: %w[pending indexing indexed failed] }
end
```

### Columns

| Column | Type | Default | Notes |
|--------|------|---------|-------|
| `hotel_id` | bigint | — | FK, not null |
| `title` | string | — | not null |
| `source_type` | string | — | `text` or `pdf` |
| `category` | string | — | `policy`, `faq`, or `general_info` |
| `language` | string | `"en"` | |
| `embedding_status` | string | `"pending"` | `pending`, `indexing`, `indexed`, or `failed` |
| `tags` | text[] | `[]` | PG native array |
| `version` | integer | `1` | |
| `effective_date` | date | nullable | null = forever |
| `content` | text | nullable | raw text for `source_type: "text"` |
| `metadata` | jsonb | `{}` | |
| `file` | — | — | Active Storage attachment |

### Indexes
- `hotel_id`
- `(hotel_id, category)`

---

## `hotel_knowledge_chunks`

```ruby
class HotelKnowledgeChunk < ApplicationRecord
  belongs_to :document, class_name: "HotelKnowledgeDocument",
                        foreign_key: :hotel_knowledge_document_id
  has_neighbors :embedding
end
```

### Columns

| Column | Type | Default | Notes |
|--------|------|---------|-------|
| `hotel_knowledge_document_id` | bigint | — | FK, not null |
| `content` | text | — | not null |
| `embedding` | vector(1536) | nullable | pgvector column |
| `chunk_index` | integer | — | not null |
| `token_count` | integer | nullable | |
| `metadata` | jsonb | `{}` | |

### Indexes
- `(hotel_knowledge_document_id, chunk_index)` unique

---

## Hotel Model Addition

```ruby
has_many :knowledge_documents, class_name: "HotelKnowledgeDocument", dependent: :destroy
has_many :knowledge_diagnostics, class_name: "HotelKnowledgeDiagnostic", dependent: :destroy
```

---

## `hotel_knowledge_diagnostics`

```ruby
class HotelKnowledgeDiagnostic < ApplicationRecord
  belongs_to :hotel
  belongs_to :prospect, optional: true
  belongs_to :prospect_message, optional: true

  validates :question, :intent, :diagnostic_status, presence: true
  validates :diagnostic_status, inclusion: { in: %w[open reviewed resolved dismissed] }
  validates :suggested_category, inclusion: { in: %w[policy faq general_info] }, allow_blank: true
end
```

### Columns

| Column | Type | Default | Notes |
|--------|------|---------|-------|
| `hotel_id` | bigint | — | FK, not null |
| `prospect_id` | bigint | nullable | optional guest/prospect link |
| `prospect_message_id` | bigint | nullable | optional source message link |
| `question` | text | — | guest/staff knowledge question |
| `intent` | string | — | producer intent such as `hotel_information` |
| `topic` | string | nullable | more specific routed topic |
| `routed_categories` | text[] | `[]` | categories searched first |
| `fallback_categories` | text[] | `[]` | fallback categories searched |
| `answer_mode` | string | nullable | `unavailable`, `fallback`, `deterministic`, etc. |
| `answer` | text | nullable | generated or fallback answer |
| `success` | boolean | `false` | tool result success flag |
| `source` | string | nullable | producer/tool source |
| `knowledge_matches` | jsonb | `[]` | matched chunk summaries |
| `match_count` | integer | `0` | stored count of matches |
| `best_distance` | decimal | nullable | lowest vector distance when present |
| `diagnostic_status` | string | `"open"` | `open`, `reviewed`, `resolved`, `dismissed` |
| `suggested_category` | string | nullable | `policy`, `faq`, or `general_info` |
| `metadata` | jsonb | `{}` | producer/tool context |

### Indexes
- `hotel_id`
- `created_at`
- `diagnostic_status`
- `answer_mode`
- `suggested_category`

## Migration Details

### PGVector Extension
```ruby
enable_extension "vector" unless extension_enabled?("vector")
```

### Vector Index (post-embedding population)
```ruby
add_index :hotel_knowledge_chunks, :embedding,
  using: :ivfflat,
  opclass: :vector_cosine_ops
```
