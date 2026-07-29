# frozen_string_literal: true

module HotelPortal
  module AccountsReceivable
    # Backs the External Accounts index, which merges two sources into one table:
    # linked corporate relationships (paginated) and outstanding invitations
    # (pinned above the paginated body, never paginated).
    class CorporateAccountsPresenter
      PER_PAGE = 25

      ALL_TAB = "all"

      STATUS_OPTIONS = [
        [ "Active", "active" ],
        [ "Suspended", "suspended" ],
        [ "Pending", "pending" ],
        [ "Expired", "expired" ]
      ].freeze

      # Statuses that only exist on a relationship, and those that only exist on an
      # invitation. Selecting one suppresses the other source entirely.
      RELATIONSHIP_STATUSES = %w[active suspended].freeze
      INVITATION_STATUSES = %w[pending expired].freeze

      attr_reader :hotel, :params

      def initialize(hotel:, params:)
        @hotel = hotel
        @params = params
      end

      # Invitation rows, rendered above the paginated body and outside pagination.
      def pinned_rows
        @pinned_rows ||= scoped_invitations.map { |invitation| PendingRow.new(invitation) }
      end

      def paginated_rows
        @paginated_rows ||= paginated_relationships.map { |relationship| Row.new(relationship, credit_exposures[relationship]) }
      end

      def any_rows?
        pinned_rows.any? || paginated_rows.any?
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

      def selected_account_type
        @selected_account_type ||= HotelCorporateAccount::ACCOUNT_TYPES.include?(params[:account_type].to_s) ? params[:account_type].to_s : nil
      end

      # Tab segments for the account-type filter. Counts honour the active search and
      # status filter but not the tab itself, so the row of counts stays comparable.
      def account_type_tabs
        @account_type_tabs ||= begin
          counts = account_type_counts

          [ { name: ALL_TAB, label: "All", count: counts.values.sum, active: selected_account_type.nil? } ] +
            HotelCorporateAccount::ACCOUNT_TYPES.map do |account_type|
              {
                name: account_type,
                label: account_type.humanize,
                count: counts.fetch(account_type, 0),
                active: selected_account_type == account_type
              }
            end
        end
      end

      # The active filter set, so an action that re-renders the results frame can put
      # the operator back exactly where they were.
      def filter_params
        {
          query: query.presence,
          status: selected_status,
          account_type: selected_account_type,
          page: params[:page].presence
        }.compact
      end

      def filters_active?
        query.present? || selected_status.present? || selected_account_type.present?
      end

      private

      # --- relationships ------------------------------------------------------

      def relationships_included?
        selected_status.blank? || selected_status.in?(RELATIONSHIP_STATUSES)
      end

      def base_scope
        hotel.hotel_corporate_accounts
          .includes(:hotel, corporate_account: :users)
          .order(created_at: :desc)
      end

      # Everything except the account-type tab, so tab counts can reuse it.
      def filtered_relationships
        return @filtered_relationships if defined?(@filtered_relationships)

        @filtered_relationships =
          if relationships_included?
            scope = base_scope
            scope = search_scope(scope) if query.present?
            scope = scope.where(status: selected_status) if selected_status.present?
            scope
          else
            HotelCorporateAccount.none
          end
      end

      def scoped_relationships
        @scoped_relationships ||= begin
          scope = filtered_relationships
          scope = scope.where(account_type: selected_account_type) if selected_account_type.present?
          scope
        end
      end

      def paginated_relationships
        @paginated_relationships ||= scoped_relationships.page(params[:page]).per(PER_PAGE)
      end

      def search_scope(scope)
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
            query: search_pattern
          )
          .distinct
      end

      def search_pattern
        "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      end

      def credit_exposures
        @credit_exposures ||= ArInvoices::CreditExposure.for_relationships(paginated_relationships.to_a)
      end

      # --- invitations --------------------------------------------------------

      def invitations_included?
        selected_status.blank? || selected_status.in?(INVITATION_STATUSES)
      end

      def base_invitation_scope
        hotel.corporate_invitations
          .unaccepted
          .includes(:invited_by_user)
          .order(created_at: :desc)
      end

      # Everything except the account-type tab, so tab counts can reuse it. Loaded
      # eagerly: this set is unpaginated and small, and account_type lives in the jsonb
      # metadata column, so grouping and filtering on it happen in Ruby rather than SQL.
      def filtered_invitations
        @filtered_invitations ||=
          if invitations_included?
            scope = base_invitation_scope
            scope = scope.where("invitations.email ILIKE ?", search_pattern) if query.present?
            scope = scope.pending if selected_status == "pending"
            scope = scope.expired if selected_status == "expired"
            scope.to_a
          else
            []
          end
      end

      def scoped_invitations
        @scoped_invitations ||=
          if selected_account_type.present?
            filtered_invitations.select { |invitation| invitation.account_type == selected_account_type }
          else
            filtered_invitations
          end
      end

      # --- tab counts ---------------------------------------------------------

      # One grouped query for relationships; invitations are already loaded.
      def account_type_counts
        relationship_counts = filtered_relationships.except(:includes, :order, :limit, :offset).reorder(nil).group(:account_type).count
        invitation_counts = filtered_invitations.group_by(&:account_type).transform_values(&:size)

        relationship_counts
          .merge(invitation_counts) { |_account_type, relationships, invitations| relationships + invitations }
          .reject { |account_type, _count| account_type.blank? }
      end

      # --- rows ---------------------------------------------------------------

      class Row
        attr_reader :relationship, :credit_exposure

        def initialize(relationship, credit_exposure)
          @relationship = relationship
          @credit_exposure = credit_exposure
        end

        delegate :corporate_account, :agent_code, :status, :active?, to: :relationship

        def id = relationship.id

        def dom_id = "external-account-row-#{id}"

        def pending? = false

        def account_name
          corporate_account.name
        end

        def account_type_label
          relationship.account_type.humanize
        end

        def contact_email
          corporate_account.users.min_by(&:id)&.email || relationship.contact_email
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

        def status_variant
          active? ? :success : :warning
        end

        def created_on_label
          relationship.created_at.strftime("%d %b %Y")
        end
      end

      # An invitation rendered with the same reader set as Row so the table partial
      # never branches on source. Account name and agent code do not exist until the
      # recipient accepts.
      class PendingRow
        attr_reader :invitation

        def initialize(invitation)
          @invitation = invitation
        end

        def id = invitation.id

        def dom_id = "external-invitation-row-#{id}"

        def pending? = true

        def expired? = invitation.expired?

        def account_name = nil

        def agent_code = nil

        def credit_exposure = nil

        def account_type_label
          invitation.account_type.to_s.humanize
        end

        def contact_email
          invitation.email
        end

        def terms_label
          "#{invitation.relationship_type.to_s.humanize} · #{invitation.payment_terms_days.present? ? "#{invitation.payment_terms_days} days" : 'No terms'}"
        end

        def proposed_credit_limit
          invitation.credit_limit
        end

        def proposed_credit_currency
          invitation.credit_currency
        end

        def status
          expired? ? "expired" : "pending"
        end

        def status_label
          status.humanize
        end

        def status_variant
          expired? ? :destructive : :info
        end

        def expiry_label
          "#{expired? ? 'Expired' : 'Expires'} #{invitation.expires_at.strftime('%d %b %Y')}"
        end

        def created_on_label
          invitation.created_at.strftime("%d %b %Y")
        end
      end
    end
  end
end
