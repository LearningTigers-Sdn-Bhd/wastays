# frozen_string_literal: true

class DropLastIntentFromConversationStates < ActiveRecord::Migration[8.0]
  def change
    # Written on every turn, read by nothing. They are the deleted interpreter's
    # notes: `last_intent` recorded a classification the loop no longer makes,
    # and `last_action_name` a resolver step that now lives in the tool that
    # took it. Every routing decision they used to explain is asserted through
    # the reply and the booking state instead.
    remove_column :prospect_conversation_states, :last_intent, :string
    remove_column :prospect_conversation_states, :last_action_name, :string
  end
end
