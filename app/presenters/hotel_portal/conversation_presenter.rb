# frozen_string_literal: true

module HotelPortal
  # One row in the inbox, and the header above an open thread.
  #
  # A prospect may have no name and no phone -- someone typing into the public
  # concierge page before they have said who they are -- so every label here
  # has to survive that rather than render a blank row.
  class ConversationPresenter
    CHANNEL_LABELS = { "web" => "Web", "whatsapp" => "WhatsApp", "api" => "API" }.freeze
    CHANNEL_ICONS = { "web" => "globe", "whatsapp" => "message-circle", "api" => "webhook" }.freeze

    def initialize(conversation, view:)
      @conversation = conversation
      @view = view
    end

    attr_reader :conversation

    delegate :id, :mode, :status, :channel, :prospect, :assigned_user,
             :last_message_at, :human?, :open?, :human_requested?, to: :conversation

    def display_name
      prospect.name.presence || prospect.phone_number.presence || "Unnamed guest"
    end

    # Only worth showing when it is not already doing duty as the name.
    def subtitle
      prospect.phone_number.presence if prospect.name.present?
    end

    def channel_label = CHANNEL_LABELS.fetch(channel, channel.humanize)
    def channel_icon = CHANNEL_ICONS.fetch(channel, "message-circle")

    # A prospect linked to a guest has booked before. That is the single most
    # useful thing a staff member can know before they read a word.
    def returning_guest? = prospect.guest_id.present?

    def last_activity
      return "No messages yet" if last_message_at.blank?

      "#{view.time_ago_in_words(last_message_at)} ago"
    end

    # A guest who has asked for a person is still being answered by the bot, so
    # "bot handling" is true and beside the point: what the reader needs to know
    # is that somebody is waiting for them.
    def status_badge
      return { label: "Closed", variant: :neutral } unless open?
      return { label: "Waiting for staff", variant: :warning } if human?
      return { label: "Asked for a person", variant: :warning } if human_requested?

      { label: "Bot handling", variant: :outline }
    end

    def assignee_label
      assigned_user&.name.presence || "Unassigned"
    end

    def unread_count
      @unread_count ||= conversation.messages.unread.from_guest.count
    end

    def unread? = unread_count.positive?

    private

    attr_reader :view
  end
end
