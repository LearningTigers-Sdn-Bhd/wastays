# frozen_string_literal: true

# Every message belongs to a thread, and the column finally says so.
#
# `BackfillConversationsFromProspects` gave the historical rows a conversation,
# and every writer since -- the web chat, the assistant's persister, the
# session loader, and the five services that write a system line -- passes one.
# The nullable column was the last place claiming otherwise, and the model was
# carrying `conversation.blank?` guards on the broadcasts and the touch to
# honour a row that can no longer be written.
#
# The backfill below is for orphans that predate nothing in particular: a row
# whose thread went missing takes the prospect's open one, or a fresh one on
# the channel the old traffic arrived on. Deleting a guest's message to satisfy
# a constraint would be the wrong trade.
class RequireConversationOnProspectMessages < ActiveRecord::Migration[8.1]
  class Prospect < ActiveRecord::Base; end
  class ProspectMessage < ActiveRecord::Base; end
  class Conversation < ActiveRecord::Base; end

  def up
    ProspectMessage.where(conversation_id: nil).distinct.pluck(:prospect_id).each do |prospect_id|
      messages = ProspectMessage.where(prospect_id: prospect_id, conversation_id: nil)
      messages.update_all(conversation_id: conversation_for(prospect_id, messages))
    end

    change_column_null :prospect_messages, :conversation_id, false
  end

  def down
    change_column_null :prospect_messages, :conversation_id, true
  end

  private

  def conversation_for(prospect_id, messages)
    existing = Conversation.where(prospect_id: prospect_id, status: "open").order(:id).first
    return existing.id if existing

    prospect = Prospect.find(prospect_id)
    last_at = messages.maximum(:sent_at) || messages.maximum(:created_at)

    Conversation.create!(
      hotel_id: prospect.hotel_id,
      prospect_id: prospect_id,
      channel: "whatsapp",
      mode: "bot",
      status: "open",
      last_message_at: last_at,
      last_guest_message_at: messages.where(direction: "inbound").maximum(:sent_at),
      created_at: prospect.created_at,
      updated_at: prospect.updated_at
    ).id
  end
end
