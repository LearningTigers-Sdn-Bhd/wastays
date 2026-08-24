# frozen_string_literal: true

# Records that the guest asked to be put through to a person.
#
# Deliberately not a change of `mode`. Mode decides who is *allowed* to answer,
# and flipping it to human on a guest's tap would silence the assistant the
# instant they asked -- leaving them with nothing at all until somebody happens
# to open the inbox. This is a request, so the bot keeps answering until a
# person actually takes the thread over.
#
# Nullable and unindexed on purpose: it is read alongside `mode` on the small
# set of open threads the inbox already filters, which the existing
# (hotel_id, mode, status) index covers.
class AddHumanRequestedAtToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :human_requested_at, :datetime
  end
end
