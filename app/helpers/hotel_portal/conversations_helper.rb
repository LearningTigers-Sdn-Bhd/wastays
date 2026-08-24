# frozen_string_literal: true

module HotelPortal
  module ConversationsHelper
    # Status and filter are separate query params, but a reader is making one
    # choice, so they are presented as one strip. "Waiting" is listed before
    # "Closed" because it is the only tab that means somebody is owed an answer.
    def conversation_inbox_tabs(counts)
      [
        { name: "all", label: "Open", icon: "inbox", count: counts[:open], count_key: :open, params: {} },
        { name: "unread", label: "Unread", icon: "mail", count: counts[:unread], count_key: :unread, params: { filter: "unread" } },
        { name: "awaiting_staff", label: "Waiting", icon: "user-round", count: counts[:awaiting_staff], count_key: :awaiting_staff, params: { filter: "awaiting_staff" } },
        { name: "closed", label: "Closed", icon: "archive", count: nil, count_key: nil, params: { status: "closed" } }
      ]
    end

    # The id one number is updated at. Named here rather than at either end so
    # the strip that renders it and the broadcast that refreshes it cannot
    # disagree about what it is called.
    def conversation_count_id(key) = "conversation-count-#{key}"

    def conversation_presenter(conversation)
      HotelPortal::ConversationPresenter.new(conversation, view: self)
    end

    # Who said it, in the words a staff member would use out loud.
    def conversation_message_author(message)
      case message.sender_role
      when "guest" then "Guest"
      when "bot" then "Assistant"
      when "staff" then message.sender_user&.name.presence || "Staff"
      else "System"
      end
    end
  end
end
