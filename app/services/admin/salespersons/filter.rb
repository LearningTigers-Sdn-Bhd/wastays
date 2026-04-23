module Admin
  module Salespersons
    class Filter
      def initialize(scope, query)
        @scope = scope
        @query = query
      end

      def call
        filtered_scope = @scope.where(role: "salesperson").includes(:assigned_hotels)
        return filtered_scope if @query.blank?

        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query.downcase)}%"
        filtered_scope.left_outer_joins(:assigned_hotels)
          .where(
            "LOWER(users.name) LIKE :query OR LOWER(users.email) LIKE :query OR LOWER(hotels.name) LIKE :query",
            query: pattern
          )
          .distinct
      end

      def self.matches?(salesperson, query)
        return true if query.blank?

        haystack = [
          salesperson.name,
          salesperson.email,
          salesperson.assigned_hotels.map(&:name).join(" ")
        ].join(" ").downcase

        haystack.include?(query.downcase)
      end
    end
  end
end
