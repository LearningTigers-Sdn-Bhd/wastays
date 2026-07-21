# frozen_string_literal: true

module HotelPortal
  module AccountsReceivable
    class CorporateAccountsPresenter
      PER_PAGE = 25

      STATUS_OPTIONS = [ [ "Active", "active" ], [ "Suspended", "suspended" ] ].freeze

      attr_reader :hotel, :params

      def initialize(hotel:, params:)
        @hotel = hotel
        @params = params
      end

      def paginated_rows
        @paginated_rows ||= paginated_relationships.map { |relationship| Row.new(relationship, credit_exposures[relationship]) }
      end

      def pagination
        paginated_relationships
      end

      def query
        params[:query].to_s.strip
      end

      def status_options
        STATUS_OPTIONS
      end

      def selected_status
        @selected_status ||= STATUS_OPTIONS.any? { |_, value| value == params[:status].to_s } ? params[:status].to_s : nil
      end

      def filters_active?
        query.present? || selected_status.present?
      end

      private

      def base_scope
        hotel.hotel_corporate_accounts
          .includes(corporate_account: :users)
          .order(created_at: :desc)
      end

      def filtered_relationships
        @filtered_relationships ||= begin
          scope = base_scope
          scope = search_scope(scope) if query.present?
          scope = scope.where(status: selected_status) if selected_status.present?
          scope
        end
      end

      def paginated_relationships
        @paginated_relationships ||= filtered_relationships.page(params[:page]).per(PER_PAGE)
      end

      def search_scope(scope)
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"

        scope
          .left_joins(corporate_account: :users)
          .where(
            <<~SQL.squish,
              accounts.name ILIKE :query
              OR hotel_corporate_accounts.agent_code ILIKE :query
              OR hotel_corporate_accounts.contact_email ILIKE :query
              OR hotel_corporate_accounts.contact_phone ILIKE :query
              OR users.email ILIKE :query
            SQL
            query: pattern
          )
          .distinct
      end

      def credit_exposures
        @credit_exposures ||= paginated_relationships.index_with do |relationship|
          ArInvoices::CreditExposure.call(hotel_corporate_account: relationship)
        end
      end

      class Row
        attr_reader :relationship, :credit_exposure

        def initialize(relationship, credit_exposure)
          @relationship = relationship
          @credit_exposure = credit_exposure
        end

        delegate :corporate_account, :agent_code, :status, :active?, to: :relationship

        def account_name
          corporate_account.name
        end

        def account_type_label
          relationship.account_type.humanize
        end

        def contact_email
          corporate_account.users.first&.email || relationship.contact_email
        end

        def contact_phone
          relationship.contact_phone
        end

        def terms_label
          "#{relationship.relationship_type.humanize} · #{relationship.payment_terms_days.present? ? "#{relationship.payment_terms_days} days" : 'No terms'}"
        end

        def status_label
          status.humanize
        end

        def created_on_label
          relationship.created_at.strftime("%d %b %Y")
        end
      end
    end
  end
end
