# frozen_string_literal: true

# Messages gain a thread, an author, and a read flag.
#
# `direction` (inbound/outbound/system) cannot say who wrote an outbound
# message -- the bot and a staff reply both land as "outbound" -- so the inbox
# had no way to render "Siti replied" differently from "the bot replied".
# `sender_role` is that missing axis; `direction` keeps its existing meaning.
#
# `conversation_id` stays nullable in this release. The backfill runs right
# after this, but old code deployed alongside the migration can still write a
# message without a thread, so the NOT NULL constraint waits for the release
# after the one that ships the new writers.
class AddConversationFieldsToProspectMessages < ActiveRecord::Migration[8.1]
  def change
    add_reference :prospect_messages, :conversation, foreign_key: true, index: false

    add_column :prospect_messages, :sender_role, :string
    add_reference :prospect_messages, :sender_user, foreign_key: { to_table: :users }
    add_column :prospect_messages, :read_at, :datetime

    # Rendering one thread in order.
    add_index :prospect_messages, [ :conversation_id, :sent_at ]

    # The unread badge, counted per hotel via the conversation.
    add_index :prospect_messages,
              [ :conversation_id ],
              where: "read_at IS NULL",
              name: "index_prospect_messages_on_conversation_when_unread"
  end
end
