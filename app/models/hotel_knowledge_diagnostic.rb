# frozen_string_literal: true

class HotelKnowledgeDiagnostic < ApplicationRecord
  STATUSES = %w[open reviewed resolved dismissed].freeze
  SUGGESTED_CATEGORIES = %w[policy faq general_info].freeze

  belongs_to :hotel
  belongs_to :prospect, optional: true
  belongs_to :prospect_message, optional: true

  validates :question, :intent, :diagnostic_status, presence: true
  validates :diagnostic_status, inclusion: { in: STATUSES }
  validates :suggested_category, inclusion: { in: SUGGESTED_CATEGORIES }, allow_blank: true
  validates :match_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent_first, -> { order(created_at: :desc) }
  scope :open, -> { where(diagnostic_status: "open") }
  scope :unavailable_or_weak, -> {
    where(answer_mode: %w[unavailable fallback weak_match])
      .or(where("best_distance > ?", HotelKnowledges::DiagnosticRecorder::WEAK_MATCH_DISTANCE))
  }
  scope :for_status, ->(status) { status.present? ? where(diagnostic_status: status) : all }
  scope :for_answer_mode, ->(mode) { mode.present? ? where(answer_mode: mode) : all }
  scope :for_suggested_category, ->(category) { category.present? ? where(suggested_category: category) : all }
  scope :created_from, ->(date) { date.present? ? where(created_at: date.beginning_of_day..) : all }
  scope :created_until, ->(date) { date.present? ? where(created_at: ..date.end_of_day) : all }
end
