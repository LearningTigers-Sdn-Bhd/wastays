# frozen_string_literal: true

class DropUnusedConversationStateCounters < ActiveRecord::Migration[8.0]
  def change
    # Neither column is written or read anywhere in the app, and neither
    # survived the interpreting pipeline they were added for: `reset_count` was
    # never incremented once resets moved into slots_payload, and
    # `last_topic_switch_at` was the old TransitionPolicy's bookkeeping.
    remove_column :prospect_conversation_states, :last_topic_switch_at, :datetime
    remove_column :prospect_conversation_states, :reset_count, :integer, default: 0, null: false
  end
end
