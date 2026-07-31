# frozen_string_literal: true

module HotelPortal
  module Requests
    # Reading a set of relations a page at a time, in one order.
    #
    # The board and the archive are the same shape: what the reader sees as one
    # list is drawn from more than one table, the rows have to be merged in an
    # order total across all of them, and the reader wants a page rather than the
    # whole thing. The board grew this first while the archive was still building
    # every row it had in order to show twenty-five, so the machinery moved here
    # rather than being written a second time.
    module Paging
      PAGE_SIZE = 25

      # One list, as far as it has been read.
      Page = Struct.new(:cards, :next_cursor, keyword_init: true) do
        def more? = next_cursor.present?
      end

      # Where a list's rows come from. A list can have more than one, and they
      # are merged in the order the cursor understands.
      Source = Struct.new(:name, :relation, :sort_column, :builder, keyword_init: true)

      private

      # Every source is ordered, and asked for one more row than the page needs
      # -- which is how the list knows there is another page without counting the
      # rest of it.
      def paged(sources, cursor: nil, limit: PAGE_SIZE)
        fetched = sources.flat_map { |source| read_source(source, cursor: cursor, limit: limit) }
        ordered = Cursor.sort(fetched)
        cards = ordered.first(limit)

        Page.new(cards: cards, next_cursor: (cursor_after(cards) if ordered.size > limit))
      end

      def read_source(source, cursor:, limit:)
        scope = source.relation.order(source.sort_column => :desc, id: :desc).limit(limit + 1)

        if cursor
          condition, binds = cursor.predicate_for(
            table: source.relation.table_name,
            column: source.sort_column,
            source: source.name
          )
          scope = scope.where(condition, binds)
        end

        # The source names itself on every row it built: the cursor orders by it,
        # and only the source knows which one it is.
        scope.map { |record| source.builder.call(record).tap { |card| card.sort_source = source.name } }
      end

      def cursor_after(cards)
        last = cards.last
        return if last.nil?

        Cursor.new(at: last[:sort_at], source: last[:sort_source], id: last[:request_id])
      end
    end
  end
end
