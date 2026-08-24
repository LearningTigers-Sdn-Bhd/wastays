# frozen_string_literal: true

class AddFullTextSearchToKnowledgeChunks < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # 'simple' rather than 'english': hotel_knowledge_documents carries a
    # language, the corpora here are not all English, and English stemming
    # would quietly degrade every chunk that is not.
    add_column :hotel_knowledge_chunks, :content_tsv, :virtual,
      type: :tsvector, as: "to_tsvector('simple', content)", stored: true

    add_index :hotel_knowledge_chunks, :content_tsv,
      using: :gin, algorithm: :concurrently,
      name: "index_hotel_knowledge_chunks_on_content_tsv"
  end
end
