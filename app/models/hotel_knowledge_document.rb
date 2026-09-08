# frozen_string_literal: true

class HotelKnowledgeDocument < ApplicationRecord
  belongs_to :hotel
  has_many :chunks, class_name: "HotelKnowledgeChunk", foreign_key: :hotel_knowledge_document_id, dependent: :destroy
  has_one_attached :file

  attribute :source_type, :string, default: "text"

  def tags=(val)
    if val.is_a?(String)
      super(val.split(",").map(&:strip).reject(&:blank?))
    else
      super(val)
    end
  end

  # A policy document is either one of the fixed cards on the Policies page or
  # a free one the hotel wrote itself. The card it belongs to is the only thing
  # that separates them, so it lives in metadata and needs no column.
  POLICY_KEYS = %w[room_terms payment_and_deposits house_rules].freeze

  validates :title, :source_type, :category, presence: true
  validates :source_type, inclusion: { in: %w[text pdf] }
  validates :category, inclusion: { in: %w[policy faq general_info] }
  validates :embedding_status, inclusion: { in: %w[pending indexing indexed failed] }

  scope :failed, -> { where(embedding_status: "failed") }
  scope :with_policy_key, ->(key) { where("metadata->>'policy_key' = ?", key.to_s) }
  scope :without_policy_key, -> { where("metadata->>'policy_key' IS NULL") }

  after_commit :enqueue_embedding_generation, on: [ :create, :update ]
  after_update_commit :broadcast_embedding_state, if: :embedding_state_changed?

  def enqueue_embedding_generation!
    return false unless hotel.ai_concierge_enabled?

    mark_embedding_indexing!
    HotelKnowledges::GenerateEmbeddingsJob.perform_later(id)
    true
  end

  def mark_embedding_indexing!
    update_embedding_state!("indexing")
  end

  # An FAQ posts its pairs from indexed form fields, which Rails hands back as a
  # Hash keyed by position. Records saved before that shape was flattened still
  # hold the Hash, so every reader comes through here instead of testing the
  # shape again in each view.
  def qa_pairs
    raw = metadata&.dig("qa_pairs")
    raw = raw.values if raw.is_a?(Hash)

    Array(raw).grep(Hash)
  end

  private

  def update_embedding_state!(status)
    previous_value = Thread.current[:skip_hotel_knowledge_embedding_enqueue]
    Thread.current[:skip_hotel_knowledge_embedding_enqueue] = true

    update!(
      embedding_status: status,
      metadata: metadata.except("last_error")
    )
  ensure
    Thread.current[:skip_hotel_knowledge_embedding_enqueue] = previous_value
  end

  def enqueue_embedding_generation
    return if Thread.current[:skip_hotel_knowledge_embedding_enqueue]
    return unless hotel.ai_concierge_enabled?
    return if embedding_state_only_change?
    return if previous_changes.key?("id") && embedding_status == "indexed"

    content_changed = previous_changes.key?("content")
    file_attached = source_type == "pdf" && file.attached?
    return unless content_changed || file_attached || previous_changes.key?("id")

    enqueue_embedding_generation!
  end

  def embedding_state_changed?
    saved_change_to_embedding_status? || saved_change_to_metadata?
  end

  def embedding_state_only_change?
    (previous_changes.keys - %w[embedding_status metadata updated_at]).empty?
  end

  def broadcast_embedding_state
    broadcast_refresh_to self
  end
end
