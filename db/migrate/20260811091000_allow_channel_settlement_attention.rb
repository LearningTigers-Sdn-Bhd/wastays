# frozen_string_literal: true

class AllowChannelSettlementAttention < ActiveRecord::Migration[8.0]
  STATUSES = %w[
    property_collection_required
    awaiting_ota_settlement
    virtual_card_not_ready
    ready_to_charge
    partially_received
    received
    underpaid
    overpaid
    failed
    cancelled
    needs_attention
    unknown
  ].freeze

  def up
    remove_check_constraint :channel_settlements, name: "channel_settlements_status_allowed"
    add_check_constraint :channel_settlements,
      "status IN ('#{STATUSES.join("', '")}')",
      name: "channel_settlements_status_allowed"
  end

  def down
    remove_check_constraint :channel_settlements, name: "channel_settlements_status_allowed"
    add_check_constraint :channel_settlements,
      "status IN ('property_collection_required', 'awaiting_ota_settlement', 'virtual_card_not_ready', 'ready_to_charge', 'partially_received', 'received', 'underpaid', 'overpaid', 'failed', 'cancelled', 'unknown')",
      name: "channel_settlements_status_allowed"
  end
end
