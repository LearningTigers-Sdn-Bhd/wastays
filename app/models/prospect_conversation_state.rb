class ProspectConversationState < ApplicationRecord
  FLOW_STATUSES = %w[active paused completed abandoned ended].freeze
  PAUSED_FLOW_TTL = 1.hour

  belongs_to :prospect

  validates :prospect_id, uniqueness: true
  validates :flow_status, presence: true, inclusion: { in: FLOW_STATUSES }

  before_validation :normalize_slots_payload

  private

  def normalize_slots_payload
    self.slots_payload = {} unless slots_payload.is_a?(Hash)
  end
end
