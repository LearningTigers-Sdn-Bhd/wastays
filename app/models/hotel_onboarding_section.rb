# frozen_string_literal: true

class HotelOnboardingSection < ApplicationRecord
  STATES = %w[not_started in_progress complete skipped needs_attention].freeze

  belongs_to :hotel

  validates :section_key, presence: true, uniqueness: { scope: :hotel_id },
                          inclusion: { in: Onboarding::SectionCatalog.keys }
  validates :state, presence: true, inclusion: { in: STATES }

  scope :in_journey_order, -> { order(Arel.sql(Onboarding::SectionCatalog.order_sql("section_key"))) }

  def resolved?
    state.in?(%w[complete skipped])
  end
end
