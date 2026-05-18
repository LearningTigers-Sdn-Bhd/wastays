# frozen_string_literal: true

class Partner < ApplicationRecord
  belongs_to :hotel

  before_validation :generate_code, if: -> { code.blank? }
  before_validation :normalize_fields

  validates :name, presence: true
  validates :code, presence: true, uniqueness: { scope: :hotel_id, case_sensitive: false }

  scope :ordered, -> { order(:name, :id) }

  private

  def generate_code
    return if name.blank?

    # Get first 3 alphanumeric characters from name, or pad with 'X' if too short
    prefix = name.gsub(/[^a-zA-Z0-9]/, "").first(3).upcase.ljust(3, "X")
    random_suffix = rand(100..999).to_s
    self.code = "#{prefix}#{random_suffix}"
  end

  def normalize_fields
    self.code = code.to_s.strip.upcase
    self.domain = domain.to_s.strip.downcase.presence
  end
end
