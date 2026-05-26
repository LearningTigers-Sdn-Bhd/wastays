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
  validates :embedding_status, inclusion: { in: %w[pending indexed failed] }
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
| `embedding_status` | string | `"pending"` | `pending`, `indexed`, or `failed` |
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
```

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
