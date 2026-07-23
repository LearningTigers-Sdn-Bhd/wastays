# frozen_string_literal: true

module HotelPortal
  module Folios
    class IndexPresenter
    FILTERS = [
      [ "all", "All" ],
      [ "open", "Open" ],
      [ "balance_due", "Balance Due" ],
      [ "refund_due", "Refund Due" ],
      [ "due_out", "Due Out" ],
      [ "closed", "Closed" ],
      [ "adjusted", "Adjusted" ]
    ].freeze

    attr_reader :hotel, :params

    def initialize(hotel:, params:)
      @hotel = hotel
      @params = params
    end

    def rows
      @rows ||= folios.map { |folio| Row.new(folio, hotel: hotel, business_date: business_date) }
    end

    def paginated_rows
      @paginated_rows ||= Kaminari.paginate_array(filtered_rows).page(params[:page]).per(25)
    end

    def attention_rows
      @attention_rows ||= rows.select(&:needs_attention?).first(5)
    end

    def show_all_attention?
      params[:attention] == "all"
    end

    def visible_attention_rows
      show_all_attention? ? rows.select(&:needs_attention?) : attention_rows
    end

    def filter_options
      FILTERS.map do |key, label|
        { key: key, label: label, count: count_for_filter(key) }
      end
    end

    def selected_filter
      FILTERS.map(&:first).include?(params[:filter].to_s) ? params[:filter].to_s : "all"
    end

    def query
      params[:query].to_s.strip
    end

    def active_filter?(key)
      selected_filter == key
    end

    def summary_cards
      [
        { label: "Open Folios", value: rows.count(&:open?), icon: "book-open", class: "bg-blue-50 text-blue-700" },
        { label: "Balance Due", value: rows.count(&:balance_due?), icon: "credit-card", class: "bg-red-50 text-red-700" },
        { label: "Refund Due", value: rows.count(&:refund_due?), icon: "rotate-ccw", class: "bg-amber-50 text-amber-700" },
        { label: "Closed Today", value: rows.count(&:closed_today?), icon: "circle-check", class: "bg-emerald-50 text-emerald-700" }
      ]
    end

    def filters_active?
      query.present? || selected_filter != "all"
    end

    private

    def folios
      @folios ||= hotel.booking_folios
                       .includes(:folio_transactions, booking: [ :refund_request, { booking_rooms: :room_type } ])
                       .order(updated_at: :desc, id: :desc)
                       .to_a
    end

    def filtered_rows
      @filtered_rows ||= rows.select { |row| matches_query?(row) && matches_filter?(row) }
    end

    def count_for_filter(key)
      rows.count { |row| matches_filter?(row, key) }
    end

    def matches_query?(row)
      return true if query.blank?

      row.search_text.include?(query.downcase)
    end

    def matches_filter?(row, filter = selected_filter)
      case filter
      when "open" then row.open?
      when "balance_due" then row.balance_due?
      when "refund_due" then row.refund_due?
      when "due_out" then row.due_out?
      when "closed" then row.closed?
      when "adjusted" then row.adjusted?
      else true
      end
    end

    def business_date
      @business_date ||= hotel.current_business_date || hotel.business_date_for(Time.current)
    end

    class Row
      attr_reader :folio, :hotel, :business_date

      def initialize(folio, hotel:, business_date:)
        @folio = folio
        @hotel = hotel
        @business_date = business_date
      end

      delegate :booking, to: :folio

      def open?
        folio.status == "open"
      end

      def closed?
        folio.status == "closed"
      end

      def balance
        @balance ||= begin
          transactions = folio.folio_transactions
          charges = transactions.select(&:charge?).sum { |transaction| transaction.amount.to_d }
          payments = transactions.select(&:payment?).sum { |transaction| transaction.amount.to_d }
          adjustments = transactions.select(&:adjustment?).sum { |transaction| transaction.amount.to_d }

          charges - payments + adjustments
        end
      end

      def balance_due?
        open? && balance.positive?
      end

      def refund_due?
        open? && balance.negative?
      end

      def due_out?
        open? && booking.check_out.in_time_zone(hotel.hotel_time_zone).to_date == business_date
      end

      def adjusted?
        folio.folio_transactions.any?(&:adjustment?)
      end

      def closed_today?
        closed? && hotel.business_day_window_for(business_date).cover?(folio.updated_at.in_time_zone(hotel.hotel_time_zone))
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
        amount = balance.abs
        suffix = balance.negative? ? " credit" : ""
        "#{currency} #{format('%.2f', amount)}#{suffix}"
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
        badges << { label: "Credit", icon: "rotate-ccw", class: green_badge_class } if refund_due?
        badges << { label: "Review", icon: "triangle-alert", class: red_badge_class } if unsynced_completed_refund?
        badges << { label: "Guest owes hotel", icon: "credit-card", class: red_badge_class } if balance_due?
        badges << { label: "Hotel owes guest", icon: "rotate-ccw", class: red_badge_class } if refund_due?
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
        return "Hotel owes guest" if refund_due?
        return "Guest owes hotel" if balance_due?
        return "Due out today with non-zero balance" if due_out? && !settled?

        "Review folio"
      end

      def needs_attention?
        balance_due? || refund_due? || (due_out? && !settled?) || unsynced_completed_refund?
      end

      def unsynced_completed_refund?
        refund_request = booking.refund_request
        return false unless refund_request&.completed?

        expected_amount = -refund_request.refund_amount.to_d
        folio.folio_transactions.none? do |transaction|
          transaction.transaction_type == "payment" &&
            (transaction.metadata || {})["refund_request_id"].to_s == refund_request.id.to_s &&
            transaction.amount.to_d == expected_amount
        end
      end

      def search_text
        [
          booking.guest_name,
          booking.confirmation_token,
          booking.guest_email,
          booking.guest_phone,
          folio.folio_number,
          folio_reference,
          booking.booking_rooms.map(&:room_number)
        ].flatten.compact.join(" ").downcase
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
