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
end
