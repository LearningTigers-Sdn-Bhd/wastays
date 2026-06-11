class PlanFeature < ApplicationRecord
  belongs_to :plan
  belongs_to :feature

  LEVELS = %w[manual basic advanced full room_allotment].freeze

  validates :feature_id, uniqueness: { scope: :plan_id }
  validates :level, inclusion: { in: LEVELS }, allow_nil: true
end
