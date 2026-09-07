# frozen_string_literal: true

module HotelPortal
  module Folios
    class IndexPresenter
    include Pagy::Method

    PER_PAGE = 25

    FILTERS = [
      [ "all", "All" ],
      [ "open", "Open" ],
      [ "balance_due", "Balance Due" ],
      [ "refund_due", "Refund Due" ],
      [ "due_out", "Due Out" ],
      [ "closed", "Closed" ],
      [ "adjusted", "Adjusted" ]
    ].freeze

    ATTENTION_FILTERS = [
      [ "all", "All" ],
      [ "balance_due", "Balance Due" ],
      [ "refund_due", "Refund Due" ],
      [ "due_out", "Due Out" ],
      [ "review", "Review" ]
    ].freeze

    attr_reader :hotel, :params, :request

    def initialize(hotel:, params:, request:, attention_only: false)
      @hotel = hotel
      @params = params
      @request = request
      @attention_only = attention_only
    end

    def attention_only?
      @attention_only
    end

    def rows
      @rows ||= pagination_pair.last.map { |folio| Row.new(folio) }
    end

    def paginated_rows
      rows
    end

    def pagination
      pagination_pair.first
    end

    def needs_attention_count
      index_query.needs_attention_count
    end

    def active_filters
      attention_only? ? ATTENTION_FILTERS : FILTERS
    end

    def filter_options
      counts = index_query.filter_counts(active_filters)
      active_filters.map do |key, label|
        { key: key, label: label, value: (key == "all" ? "" : key), count: counts.fetch(key, 0) }
      end
    end

    def selected_filter
      active_filters.map(&:first).include?(params[:filter].to_s) ? params[:filter].to_s : "all"
    end

    def query
      params[:query].to_s.strip
    end

    def active_filter?(key)
      selected_filter == key
    end

    def summary_cards
      counts = index_query.summary_counts
      [
        { label: "Open Folios", value: counts.fetch("open", 0), icon: "book-open", class: "bg-blue-50 text-blue-700" },
        { label: "Balance Due", value: counts.fetch("balance_due", 0), icon: "credit-card", class: "bg-red-50 text-red-700" },
        { label: "Refund Due", value: counts.fetch("refund_due", 0), icon: "rotate-ccw", class: "bg-amber-50 text-amber-700" },
        { label: "Closed Today", value: counts.fetch("closed_today", 0), icon: "circle-check", class: "bg-emerald-50 text-emerald-700" }
      ]
    end

    def filters_active?
      query.present? || selected_filter != "all"
    end

    private

    def pagination_pair
      @pagination_pair ||= pagy(:offset, index_query.collection, request: request, limit: PER_PAGE)
    end

    def index_query
      @index_query ||= HotelPortal::Folios::IndexQuery.new(
        hotel: hotel,
        query: query,
        filter: selected_filter,
        attention_only: attention_only?
      )
    end

    class Row
      attr_reader :folio

      def initialize(folio)
        @folio = folio
      end

      delegate :booking, to: :folio

      def open?
        folio.status == "open"
      end

      def closed?
        folio.status == "closed"
      end

      def balance
        @balance ||= folio.calculated_balance.to_d
      end

      def balance_due?
        open? && balance.positive?
      end

      def refund_due?
        open? && balance.negative?
      end

      def due_out?
        folio.calculated_due_out
      end

      def adjusted?
        folio.calculated_adjusted
      end

      def closed_today?
        folio.calculated_closed_today
      end

      def settled?
        balance.zero?
      end

      def financial_status
        return "Balance Due" if balance.positive?
        return "Refund Due" if balance.negative?

        "Settled"
      end

      def financial_status_class
        return "text-red-700" if balance.positive? || balance.negative?

        "text-emerald-700"
      end

      def financial_icon
        return "triangle-alert" if balance.positive?
        return "rotate-ccw" if balance.negative?

        "circle-check"
      end

      def amount_label
        "#{currency} #{format('%.2f', balance.abs)}"
      end

      def currency
        booking.currency.presence || "MYR"
      end

      def folio_reference
        folio.folio_reference_display.presence || booking.folio_account_reference_display.presence || folio.folio_number.to_s
      end

      def folio_account_reference
        booking.folio_account_reference_display.presence || booking.formatted_folio_number.presence || "-"
      end

      def room_label
        numbers = booking.booking_rooms.map(&:room_number).compact_blank
        numbers.any? ? "Room #{numbers.to_sentence}" : "Room -"
      end

      def stay_label
        "#{booking.check_in.strftime('%d %b')} &rarr; #{booking.check_out.strftime('%d %b %Y')}"
      end

      def status_badges
        badges = []
        badges << { label: "Due out", icon: "calendar-clock", class: red_badge_class } if due_out?
        badges << { label: "Review", icon: "triangle-alert", class: red_badge_class } if unsynced_completed_refund?
        badges
      end

      def folio_status_badge_class
        open? ? green_badge_class : red_badge_class
      end

      def folio_status_icon
        open? ? "circle-check" : "circle-alert"
      end

      def attention_icon
        return "rotate-ccw" if refund_due?
        return "alert-circle" if unsynced_completed_refund?

        "triangle-alert"
      end

      def attention_reason
        return "Completed refund is not synced to the folio" if unsynced_completed_refund?
        return "Refund due to guest" if refund_due?
        return "Balance due from guest" if balance_due?
        return "Due out today with non-zero balance" if due_out? && !settled?

        "Review folio"
      end

      def needs_attention?
        balance_due? || refund_due? || (due_out? && !settled?) || unsynced_completed_refund?
      end

      def unsynced_completed_refund?
        folio.calculated_unsynced_refund
      end

      private

      def green_badge_class
        "border-emerald-200 bg-emerald-50 text-emerald-700"
      end

      def red_badge_class
        "border-red-200 bg-red-50 text-red-700"
      end
    end
    end
  end
end
