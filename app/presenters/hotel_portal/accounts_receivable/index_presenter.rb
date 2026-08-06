# frozen_string_literal: true

module HotelPortal
  module AccountsReceivable
    class IndexPresenter
      PER_PAGE = 25

      STATUS_OPTIONS = [
        { key: "open", label: "Open", icon: "circle-dot", class: "peer-checked:border-blue-400 peer-checked:bg-blue-50 peer-checked:text-blue-700" },
        { key: "partially_paid", label: "Partially Paid", icon: "circle-dollar-sign", class: "peer-checked:border-amber-400 peer-checked:bg-amber-50 peer-checked:text-amber-700" },
        { key: "paid", label: "Paid", icon: "circle-check", class: "peer-checked:border-emerald-400 peer-checked:bg-emerald-50 peer-checked:text-emerald-700" },
        { key: "overdue", label: "Overdue", icon: "triangle-alert", class: "peer-checked:border-red-400 peer-checked:bg-red-50 peer-checked:text-red-700" },
        { key: "void", label: "Void", icon: "circle-slash", class: "peer-checked:border-border-interactive peer-checked:bg-muted peer-checked:text-foreground" }
      ].freeze

      Metric = Struct.new(:label, :amounts, :description, :icon, :class_name, keyword_init: true)
      CorporateAccountOption = Struct.new(:id, :name, keyword_init: true)

      attr_reader :hotel, :params

      def initialize(hotel:, params:)
        @hotel = hotel
        @params = params
      end

      def paginated_rows
        @paginated_rows ||= paginated_invoices.map { |invoice| Row.new(invoice) }
      end

      def pagination
        paginated_invoices
      end

      def corporate_account_options
        @corporate_account_options ||= hotel.hotel_corporate_accounts
          .includes(:corporate_account)
          .sort_by { |relationship| relationship.corporate_account.name.to_s.downcase }
          .map { |relationship| CorporateAccountOption.new(id: relationship.id, name: relationship.corporate_account.name) }
      end

      def status_options
        STATUS_OPTIONS
      end

      def selected_status
        @selected_status ||= ArInvoice::STATUSES.include?(params[:status].to_s) ? params[:status].to_s : nil
      end

      def selected_corporate_account_id
        @selected_corporate_account_id ||= begin
          requested_id = params[:hotel_corporate_account_id].to_s
          corporate_account_options.any? { |option| option.id.to_s == requested_id } ? requested_id : nil
        end
      end

      def due_on
        @due_on ||= parse_date(params[:due_on])
      end

      def selected_balance
        @selected_balance ||= params[:balance].to_s == "outstanding" ? "outstanding" : nil
      end

      def query
        params[:query].to_s.strip
      end

      def filters_active?
        query.present? || selected_status.present? || selected_corporate_account_id.present? || due_on.present? || selected_balance.present?
      end

      def pagination_params
        {
          query: query.presence,
          status: selected_status,
          hotel_corporate_account_id: selected_corporate_account_id,
          due_on: due_on&.iso8601,
          balance: selected_balance
        }.compact
      end

      def summary_metrics
        [
          Metric.new(
            label: "Open AR",
            amounts: formatted_amounts(open_ar_amounts),
            description: "Outstanding corporate balances",
            icon: "wallet-cards",
            class_name: "bg-blue-50 text-blue-700"
          ),
          Metric.new(
            label: "Overdue",
            amounts: formatted_amounts(overdue_amounts),
            description: "Past the business due date",
            icon: "triangle-alert",
            class_name: "bg-red-50 text-red-700"
          ),
          Metric.new(
            label: "Due Soon",
            amounts: formatted_amounts(due_soon_amounts),
            description: "Due within the next 7 days",
            icon: "calendar-clock",
            class_name: "bg-amber-50 text-amber-700"
          ),
          Metric.new(
            label: "Paid This Month",
            amounts: formatted_amounts(paid_this_month_amounts),
            description: business_date.strftime("%B %Y receipts"),
            icon: "badge-check",
            class_name: "bg-emerald-50 text-emerald-700"
          )
        ]
      end

      private

      def base_scope
        hotel.ar_invoices
          .order(due_on: :asc, issued_on: :desc, invoice_number: :desc)
      end

      def filtered_invoices
        @filtered_invoices ||= begin
          scope = base_scope
          scope = search_scope(scope) if query.present?
          scope = scope.where(status: selected_status) if selected_status.present?
          scope = scope.where(hotel_corporate_account_id: selected_corporate_account_id) if selected_corporate_account_id.present?
          scope = scope.where(due_on: due_on) if due_on.present?
          scope = scope.with_open_balance if selected_balance == "outstanding"
          scope
        end
      end

      def paginated_invoices
        @paginated_invoices ||= filtered_invoices.page(params[:page]).per(PER_PAGE)
      end

      def search_scope(scope)
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"

        scope
          .eager_load(booking_folio: :booking, hotel_corporate_account: :corporate_account)
          .where(
            <<~SQL.squish,
              CAST(ar_invoices.invoice_number AS TEXT) ILIKE :query
              OR accounts.name ILIKE :query
              OR bookings.confirmation_token ILIKE :query
              OR CAST(booking_folios.folio_number AS TEXT) ILIKE :query
              OR bookings.folio_account_reference ILIKE :query
            SQL
            query: pattern
          )
      end

      def open_ar_amounts
        grouped_outstanding(hotel.ar_invoices.with_open_balance)
      end

      def overdue_amounts
        grouped_outstanding(hotel.ar_invoices.with_open_balance.where(ArInvoice.arel_table[:due_on].lt(business_date)))
      end

      def due_soon_amounts
        grouped_outstanding(hotel.ar_invoices.with_open_balance.where(due_on: business_date..(business_date + 7.days)))
      end

      def paid_this_month_amounts
        hotel.ar_payments
          .where(received_at: business_date.beginning_of_month..business_date.end_of_month)
          .group(:currency)
          .sum(:amount)
      end

      def grouped_outstanding(scope)
        scope.group(:currency).sum(:outstanding_amount)
      end

      def formatted_amounts(amounts)
        normalized = amounts.transform_keys(&:to_s)
        normalized[hotel.default_currency] = 0.to_d if normalized.empty?

        normalized.sort.map do |currency, amount|
          "#{currency} #{format('%.2f', amount.to_d)}"
        end
      end

      def business_date
        @business_date ||= hotel.current_business_date || hotel.business_date_for(Time.current)
      end

      def parse_date(value)
        Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end

      class Row
        attr_reader :invoice

        def initialize(invoice)
          @invoice = invoice
        end

        delegate :booking, :booking_folio, to: :invoice

        def invoice_label
          invoice.formatted_invoice_number
        end

        def corporate_account_name
          invoice.corporate_account.name
        end

        def booking_reference
          booking.confirmation_token
        end

        def folio_reference
          booking_folio.folio_reference_display
        end

        def source_label
          "Booking #{booking_reference} · Folio #{folio_reference}"
        end

        def issued_on_label
          invoice.issued_on.strftime("%d %b %Y")
        end

        def due_on_label
          invoice.due_on.strftime("%d %b %Y")
        end

        def outstanding_amount_label
          money_label(invoice.outstanding_amount)
        end

        def status_label
          invoice.status.humanize
        end

        def status_class
          case invoice.status
          when "open" then "border-blue-200 bg-blue-50 text-blue-700"
          when "partially_paid" then "border-amber-200 bg-amber-50 text-amber-700"
          when "paid" then "border-emerald-200 bg-emerald-50 text-emerald-700"
          when "overdue" then "border-red-200 bg-red-50 text-red-700"
          else "border-border bg-muted text-muted-foreground"
          end
        end

        private

        def money_label(amount)
          "#{invoice.currency} #{format('%.2f', amount.to_d)}"
        end
      end
    end
  end
end
