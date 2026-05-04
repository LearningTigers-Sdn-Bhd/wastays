class ProspectConversationState < ApplicationRecord
  FLOW_STATUSES = %w[active paused completed abandoned].freeze
  PAUSED_FLOW_TTL = 1.hour

  belongs_to :prospect

  validates :prospect_id, uniqueness: true
  validates :flow_status, presence: true, inclusion: { in: FLOW_STATUSES }

  before_validation :normalize_slots_payload

  def paused_flows
    Array(slots_payload["paused_flows"]).select { |flow| flow.is_a?(Hash) }
  end

  private

  def normalize_slots_payload
    self.slots_payload = {} unless slots_payload.is_a?(Hash)
  end

  def parse_time(value)
    return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
    return if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
