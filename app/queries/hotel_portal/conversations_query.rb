# frozen_string_literal: true

module HotelPortal
  # The inbox list: one hotel's threads, most recently active first.
  #
  # `last_message_at` is denormalised onto the conversation precisely so this
  # query does not have to reach into messages to sort -- an inbox is read far
  # more often than it is written.
  class ConversationsQuery
    STATUSES = %w[open closed].freeze
    FILTERS = %w[all unread awaiting_staff].freeze

    def initialize(hotel:, params: {})
      @hotel = hotel
      @params = params || {}
    end

    def call
      relation = base_relation
      relation = filter_by_status(relation)
      relation = filter_by_mode(relation)
      relation = search(relation)
      relation.recent_first.order(id: :desc)
    end

    def status = permitted(:status, STATUSES) || "open"
    def filter = permitted(:filter, FILTERS) || "all"

    # Status and filter are two params but one choice as far as the reader is
    # concerned, so the inbox presents them as a single strip of tabs.
    def active_tab
      return "closed" if status == "closed"

      filter
    end

    def counts
      scoped = base_relation.where(status: "open")

      {
        open: scoped.count,
        awaiting_staff: scoped.awaiting_staff.count,
        unread: scoped.where(id: unread_conversation_ids).count
      }
    end

    private

    attr_reader :hotel, :params

    # The prospect is always rendered (name, phone, whether they became a
    # guest), so it is loaded with the list rather than once per row.
    def base_relation
      Conversation.for_hotel(hotel).includes(prospect: :guest, assigned_user: {})
    end

    def filter_by_status(relation)
      relation.where(status: status)
    end

    def filter_by_mode(relation)
      case filter
      when "awaiting_staff" then relation.awaiting_staff
      when "unread" then relation.where(id: unread_conversation_ids)
      else relation
      end
    end

    def search(relation)
      term = params[:q].to_s.strip
      return relation if term.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
      relation
        .joins(:prospect)
        .where("prospects.name ILIKE :term OR prospects.phone_number ILIKE :term", term: pattern)
    end

    # A thread counts as unread when the guest has written something nobody has
    # opened. A bot reply nobody read is not something staff need chasing.
    def unread_conversation_ids
      ProspectMessage
        .where(read_at: nil, sender_role: "guest")
        .where.not(conversation_id: nil)
        .select(:conversation_id)
    end

    def permitted(key, allowed)
      value = params[key].to_s
      allowed.include?(value) ? value : nil
    end
  end
end
