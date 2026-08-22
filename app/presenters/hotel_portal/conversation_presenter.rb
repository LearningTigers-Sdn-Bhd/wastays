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

    # Enough of the languages a Malaysian hotel actually sees to spell one out.
    # Anything else shows its code rather than nothing: "PT" is still more use
    # to a reader than a row that keeps quiet about being in Portuguese.
    LANGUAGE_LABELS = {
      "ms" => "Malay", "id" => "Indonesian", "zh" => "Chinese", "ta" => "Tamil",
      "ar" => "Arabic", "th" => "Thai", "vi" => "Vietnamese", "ja" => "Japanese",
      "ko" => "Korean", "hi" => "Hindi", "fr" => "French", "de" => "German",
      "es" => "Spanish", "ru" => "Russian"
    }.freeze

    def initialize(conversation, view:)
      @conversation = conversation
      @view = view
    end

    attr_reader :conversation

    delegate :id, :mode, :status, :channel, :prospect, :assigned_user, :language,
             :last_message_at, :human?, :open?, :human_requested?, :translated?,
             :reply_window_closes_at, to: :conversation

    # Below this, the clock is the thing a reader should act on rather than a
    # detail of the row, so the chip stops being quiet furniture.
    REPLY_WINDOW_URGENT = 4.hours

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

    # Nil for a thread in English, so the row says nothing in the ordinary case
    # and the chip means "this one is not in your language".
    def language_label
      return unless translated?

      LANGUAGE_LABELS.fetch(language, language.upcase)
    end

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

    # How long WhatsApp will still carry a reply, or nil where there is no such
    # clock -- which is most threads, so the row says nothing in the ordinary
    # case and the chip means "this one is running out".
    #
    # Whole hours, computed at render. It goes stale between messages, because
    # nothing re-renders a row purely because time passed. That is safe by
    # design: `Concierge::PostStaffReply` recomputes the blocker when the reply
    # is actually sent, so this is advice and the refusal is the authority.
    def reply_window_label
      closes_at = reply_window_closes_at
      return nil if closes_at.blank?
      return "Reply window closed" if closes_at.past?

      hours = ((closes_at - Time.current) / 1.hour).floor
      hours.zero? ? "Under 1h left" : "#{hours}h left"
    end

    # Shaped like `status_badge` so a row renders both the same way.
    def reply_window_badge
      label = reply_window_label
      return nil if label.blank? || !open?

      { label: label, variant: reply_window_variant }
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

    def reply_window_variant
      closes_at = reply_window_closes_at
      return :destructive if closes_at.past?
      return :warning if closes_at < REPLY_WINDOW_URGENT.from_now

      :neutral
    end
  end
end
