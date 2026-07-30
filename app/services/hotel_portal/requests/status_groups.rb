# frozen_string_literal: true

module HotelPortal
  module Requests
    # What the board's status filter means, across three tables that each spell
    # their statuses differently.
    #
    # "Pending" is the group of work nobody has finished, not the literal
    # status: a guest's request arrives as "pending" from the concierge page and
    # becomes "new" the moment a dispatcher takes it, and a checkout reports
    # "new" and "assigned" of its own accord. Leaving those out of the group
    # hides dispatched work from the filter that is meant to find it.
    module StatusGroups
      GROUPS = {
        "pending" => %w[pending new assigned in_progress failed].freeze,
        "completed" => %w[completed resolved].freeze,
        "cancelled" => %w[cancelled].freeze
      }.freeze

      # A checkout reports the workflow status the board reads rather than the
      # one in its own column, so its statuses are grouped by what they mean:
      # everything still owed is outstanding, whatever it happens to be called.
      CHECKOUT_GROUPS = {
        "pending" => CheckOutRequest::OPEN_STATUSES,
        "completed" => %w[completed].freeze,
        "cancelled" => %w[cancelled].freeze
      }.freeze

      # The statuses a kind stores for a group, or nil when the group narrows
      # nothing. Asked of the database, where match? is asked of a card.
      def self.statuses_for(kind:, group:)
        group = group.to_s
        return if group.blank? || group == "all"

        table = kind.to_s == "checkout" ? CHECKOUT_GROUPS : GROUPS
        table[group]
      end

      # An unknown group narrows nothing, which is how "all" and a blank filter
      # already behave.
      def self.match?(group, status)
        group = group.to_s
        return true if group.blank? || group == "all"

        statuses = GROUPS[group]
        return true if statuses.nil?

        statuses.include?(status.to_s)
      end

      # The statuses a partly typed search term could be reaching for, so that
      # typing "pend" finds work that now reads "new".
      def self.aliases_for(query)
        query = query.to_s.strip.downcase
        return [] if query.blank?

        GROUPS.flat_map { |group, statuses|
          ([ group ] + statuses).any? { |name| name.include?(query) } ? statuses : []
        }.uniq
      end
    end
  end
end
