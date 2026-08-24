class ProspectConversationState < ApplicationRecord
  FLOW_STATUSES = %w[active paused completed abandoned ended].freeze
  PAUSED_FLOW_TTL = 1.hour

  belongs_to :prospect

  validates :prospect_id, uniqueness: true
  validates :flow_status, presence: true, inclusion: { in: FLOW_STATUSES }

  before_validation :normalize_slots_payload

  # A fresh thread starts from nothing.
  #
  # The state is keyed to the prospect, not to the conversation, so it outlives
  # every thread the guest closes. Left standing, the question the old thread
  # was waiting on -- "which option?" -- is still open when the next thread
  # opens, and the first "hello" of a brand new chat is read as an answer to it.
  def reset!
    update!(
      slots_payload: {},
      pending_question: nil,
      active_topic: nil,
      active_flow: nil,
      flow_status: "active"
    )
  end

  private

  def normalize_slots_payload
    self.slots_payload = {} unless slots_payload.is_a?(Hash)
  end
end
