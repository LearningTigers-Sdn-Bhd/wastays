# frozen_string_literal: true

module HotelPortal
  module Requests
    # What the filter bar asked for, asked of the database.
    #
    # The board and the archive both used to run these over the rows after they
    # were built, which meant every row in the window had to be built before any
    # of them could be dropped -- and meant the same predicates written twice,
    # once per page. Asked here, of a relation, a column is one ordered query,
    # which is what lets it be read a page at a time.
    module Narrowing
      private

      def search_term
        @search_term ||= params[:q].to_s.strip.downcase
      end

      def search_like
        @search_like ||= "%#{ActiveRecord::Base.sanitize_sql_like(search_term)}%"
      end

      # Whether a note somebody wrote on a request is worth searching. The
      # archive is where notes are read, so it is the one that says yes.
      def search_internal_notes?
        false
      end

      def narrow(relation, kind:)
        narrow_by_search(narrow_by_status_group(relation, kind: kind), kind: kind)
      end

      def narrow_by_status_group(relation, kind:)
        statuses = StatusGroups.statuses_for(kind: kind, group: params[:status])
        return relation if statuses.nil?

        relation.where(status: statuses)
      end

      # A term naming the kind itself keeps everything of that kind, the way it
      # did when the row's kind was one of the values searched.
      def narrow_by_search(relation, kind:)
        return relation if search_term.blank?
        return relation if kind.to_s.include?(search_term)

        relation.merge(search_alternatives(relation.klass).reduce(:or))
      end

      # Each way a row can answer the search, as relations to be OR'd. Built off
      # the bare class so that only their conditions differ, which is what `or`
      # requires of them.
      def search_alternatives(klass)
        alternatives = [
          klass.where(id: klass.search(search_term).select(:id)),
          klass.where("#{klass.table_name}.status ILIKE :q", q: search_like)
        ]

        aliases = StatusGroups.aliases_for(search_term)
        alternatives << klass.where(status: aliases) if aliases.any?

        if search_internal_notes? && klass.column_names.include?("internal_notes")
          alternatives << klass.where("#{klass.table_name}.internal_notes::text ILIKE :q", q: search_like)
        end

        alternatives
      end
    end
  end
end
