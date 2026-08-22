# frozen_string_literal: true

# A conversation is one continuous exchange with one person on one channel.
#
# Until now the only grouping was `prospect_conversation_states`, which is
# `has_one` per prospect: a guest who chatted in January and came back in June
# resumed the same state -- same slots, same pending question, same flow. There
# was no such thing as a second conversation. This table is what makes one.
#
# It is deliberately channel-neutral and AI-neutral. `mode` is what stops the
# bot and a human both answering the same guest at the same time, and nothing
# here assumes a bot is involved at all: a hotel with AI switched off still
# gets a working message desk.
class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :hotel, null: false, foreign_key: true, index: false
      t.references :prospect, null: false, foreign_key: true
      t.references :assigned_user, foreign_key: { to_table: :users }

      t.string :channel, null: false, default: "web"
      t.string :mode, null: false, default: "bot"
      t.string :status, null: false, default: "open"

      t.datetime :last_message_at
      t.datetime :last_guest_message_at
      t.datetime :closed_at

      t.timestamps
    end

    # The inbox query: this hotel's open threads, newest reply first.
    add_index :conversations, [ :hotel_id, :status, :last_message_at ]

    # The "waiting for a human" filter, and the sidebar badge count.
    add_index :conversations, [ :hotel_id, :mode, :status ]

    # One live thread per person per channel. Closed ones are unlimited, so a
    # returning guest opens a fresh conversation instead of reviving an old
    # one -- enforced here rather than left to the code that resumes sessions.
    add_index :conversations,
              [ :prospect_id, :channel ],
              unique: true,
              where: "status = 'open'",
              name: "index_conversations_on_prospect_and_channel_when_open"
  end
end
