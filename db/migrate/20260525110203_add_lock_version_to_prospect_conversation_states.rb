class AddLockVersionToProspectConversationStates < ActiveRecord::Migration[8.0]
  def change
    add_column :prospect_conversation_states, :lock_version, :integer, default: 0, null: false
  end
end
