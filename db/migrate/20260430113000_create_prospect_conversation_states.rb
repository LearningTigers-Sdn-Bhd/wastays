class CreateProspectConversationStates < ActiveRecord::Migration[8.0]
  def change
    create_table :prospect_conversation_states do |t|
      t.references :prospect, null: false, foreign_key: true, index: { unique: true }
      t.string :active_topic
      t.string :active_flow
      t.string :flow_status, null: false, default: "active"
      t.text :pending_question
      t.jsonb :slots_payload, null: false, default: {}
      t.string :last_intent
      t.string :last_action_name
      t.datetime :last_user_message_at
      t.datetime :last_topic_switch_at
      t.integer :reset_count, null: false, default: 0

      t.timestamps
    end

    add_index :prospect_conversation_states, :flow_status
    add_index :prospect_conversation_states, :active_topic
  end
end
