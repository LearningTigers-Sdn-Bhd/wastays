# frozen_string_literal: true

module HotelPortal
  module Requests
    # Where a column got to, so the next page can carry on from there.
    #
    # Not an offset. A column is live -- staff finish and archive things while
    # somebody scrolls it -- and OFFSET counts rows that have since moved, so it
    # skips and repeats them. This names the last row instead, and the next page
    # is everything sorting after it.
    #
    # A column can be drawn from three tables at once, so the order has to be
    # total across all of them: newest first, then by source, then by id
    # descending. Ids only tell rows apart within their own table, which is why
    # the source sits between the two.
    #
    # The source is not the kind the card displays -- a checkout's room cleaning
    # is a housekeeping row shown as a checkout -- so it is named separately.
    class Cursor
      SEPARATOR = "|"

      attr_reader :at, :source, :id

      def self.parse(value)
        at, source, id = value.to_s.split(SEPARATOR, 3)
        return if at.blank? || source.blank? || id.blank?

        parsed_at = Time.zone.parse(at)
        return if parsed_at.nil?

        new(at: parsed_at, source: source, id: id.to_i)
      rescue ArgumentError, TypeError
        nil
      end

      # The order every column is read in, and the order the cursor understands.
      def self.sort(rows)
        rows.sort do |a, b|
          comparison = b[:sort_at] <=> a[:sort_at]
          comparison = a[:sort_source] <=> b[:sort_source] if comparison.zero?
          comparison = b[:request_id] <=> a[:request_id] if comparison.zero?
          comparison
        end
      end

      def initialize(at:, source:, id:)
        @at = at
        @source = source.to_s
        @id = id.to_i
        freeze
      end

      def to_param
        [ at.iso8601(6), source, id ].join(SEPARATOR)
      end

      # What "after this row" means to one source, whose name is fixed. Rows of a
      # source sorting before the cursor's cannot share its instant and still
      # come after it; rows of a source sorting after it can.
      def predicate_for(table:, column:, source:)
        qualified = "#{table}.#{column}"

        if source.to_s == self.source
          [ "#{qualified} < :cursor_at OR (#{qualified} = :cursor_at AND #{table}.id < :cursor_id)",
            { cursor_at: at, cursor_id: id } ]
        elsif source.to_s < self.source
          [ "#{qualified} < :cursor_at", { cursor_at: at } ]
        else
          [ "#{qualified} <= :cursor_at", { cursor_at: at } ]
        end
      end
    end
  end
end
