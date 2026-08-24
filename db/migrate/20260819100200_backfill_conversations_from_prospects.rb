# frozen_string_literal: true

# Gives every existing message a thread to belong to.
#
# All traffic so far arrived through the external bot on a phone number, and
# every prospect had exactly one running state, so each prospect collapses to
# exactly one historical conversation. Whether it is open or closed is read
# from the flow_status that state was left in -- an abandoned January chat
# should not show up in the inbox as if the guest is still waiting.
class BackfillConversationsFromProspects < ActiveRecord::Migration[8.1]
  CLOSED_FLOW_STATUSES = %w[completed abandoned ended].freeze

  class Prospect < ActiveRecord::Base
    has_many :prospect_messages, foreign_key: :prospect_id, inverse_of: false
    has_one :prospect_conversation_state, foreign_key: :prospect_id, inverse_of: false
  end

  class ProspectMessage < ActiveRecord::Base; end
  class ProspectConversationState < ActiveRecord::Base; end
  class Conversation < ActiveRecord::Base; end

  def up
    # The author of every historical message is implied by its direction:
    # nothing but the bot has ever written an outbound one.
    ProspectMessage.where(direction: "inbound").update_all(sender_role: "guest")
    ProspectMessage.where(direction: "outbound").update_all(sender_role: "bot")
    ProspectMessage.where(direction: "system").update_all(sender_role: "system")

    Prospect.includes(:prospect_conversation_state).find_each do |prospect|
      messages = ProspectMessage.where(prospect_id: prospect.id)
      next if messages.empty?

      flow_status = prospect.prospect_conversation_state&.flow_status
      closed = CLOSED_FLOW_STATUSES.include?(flow_status)
      last_at = messages.maximum(:sent_at) || messages.maximum(:created_at)

      conversation = Conversation.create!(
        hotel_id: prospect.hotel_id,
        prospect_id: prospect.id,
        channel: "whatsapp",
        mode: "bot",
        status: closed ? "closed" : "open",
        last_message_at: last_at,
        last_guest_message_at: messages.where(direction: "inbound").maximum(:sent_at),
        closed_at: closed ? last_at : nil,
        created_at: prospect.created_at,
        updated_at: prospect.updated_at
      )

      messages.update_all(conversation_id: conversation.id)
    end
  end

  def down
    ProspectMessage.update_all(conversation_id: nil, sender_role: nil)
    Conversation.delete_all
  end
end
