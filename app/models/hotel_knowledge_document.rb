# frozen_string_literal: true

class HotelKnowledgeDocument < ApplicationRecord
  belongs_to :hotel
  has_many :chunks, class_name: "HotelKnowledgeChunk", dependent: :destroy
  has_one_attached :file

  attribute :source_type, :string, default: "text"

  def tags=(val)
    if val.is_a?(String)
      super(val.split(",").map(&:strip).reject(&:blank?))
    else
      super(val)
    end
  end

  validates :title, :source_type, :category, presence: true
  validates :source_type, inclusion: { in: %w[text pdf] }
  validates :category, inclusion: { in: %w[policy faq general_info] }
  validates :embedding_status, inclusion: { in: %w[pending indexed failed] }

  after_commit :enqueue_embedding_generation, on: [ :create, :update ]

  private

  def enqueue_embedding_generation
    return unless hotel.ai_concierge_enabled?

    content_changed = previous_changes.key?("content")
    file_attached = source_type == "pdf" && file.attached?
    return unless content_changed || file_attached || previous_changes.key?("id")

    HotelKnowledges::GenerateEmbeddingsJob.perform_later(id)
  end
end
