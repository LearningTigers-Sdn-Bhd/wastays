module NightAudits
  class Evaluate
    include Folios::NightlyChargeCalculation

    def initialize(hotel:, business_date:, phase: :post_close)
      @hotel = hotel
      @business_date = business_date.to_date
      @phase = phase.to_sym
    end

    def call
      {
        blocked_details: build_blocked_details,
        exceptions: build_exceptions,
        summary: build_summary
      }
    end

    private

    def build_summary
      {
        "arrivals_count" => hotel_bookings.checking_in_on(@business_date, @hotel.hotel_time_zone).count,
        "review_no_show_count" => hotel_bookings.where(status: "review_no_show").count,
        "no_show_count" => hotel_bookings.no_show.checking_in_on(@business_date, @hotel.hotel_time_zone).count,
        "due_out_count" => hotel_bookings.checking_out_on(@business_date, @hotel.hotel_time_zone).count,
        "checked_out_count" => hotel_bookings.completed.where(checked_out_at: @hotel.business_day_window_for(@business_date)).count,
        "in_house_count" => hotel_bookings.checked_in.where("check_in::date <= ? AND check_out::date >= ?", @business_date, @business_date).count,
        "payment_status_counts" => payment_status_counts
      }
    end

    def build_blocked_details
      details = {
        "due_out_not_checked_out" => serialize_bookings(due_out_not_checked_out, "Due out today but still not checked out"),
        "checked_in_missing_timestamp" => serialize_bookings(checked_in_missing_timestamp, "Checked-in booking is missing check-in timestamp"),
        "completed_missing_timestamp" => serialize_bookings(completed_missing_timestamp, "Completed booking is missing check-out timestamp"),
        "missing_folio" => serialize_bookings(missing_folio_bookings, "Booking requires a folio before night audit can close"),
        "missing_nightly_charges" => serialize_bookings(missing_nightly_charge_bookings, "Booking folio is missing required nightly charges"),
        "outstanding_folio_balance" => serialize_bookings(outstanding_balance_bookings, "Booking has outstanding folio balance at checkout"),
        "captured_payment_not_synced" => serialize_payment_transactions(unsynced_captured_payment_transactions, "Captured payment is not synced to the booking folio"),
        "refund_not_synced" => serialize_refund_requests(unsynced_completed_refund_requests, "Completed refund is not synced to the booking folio")
      }

      return details unless pre_close?

      details.slice(
        "due_out_not_checked_out",
        "checked_in_missing_timestamp",
        "completed_missing_timestamp",
        "missing_folio",
        "captured_payment_not_synced",
        "refund_not_synced",
        "outstanding_folio_balance"
      )
    end

    def pre_close?
      @phase == :pre_close
    end

    def build_exceptions
      exceptions = {
        "review_due_out" => serialize_bookings(review_due_out_bookings, "Due-out review carried forward"),
        "review_no_show" => serialize_bookings(review_no_show_bookings, "No-show review carried forward"),
        "open_housekeeping_requests" => serialize_requests(open_housekeeping_requests, :request_details, "Housekeeping request still open"),
        "open_complaint_requests" => serialize_requests(open_complaint_requests, :complaint_details, "Complaint request still open")
      }

      # Add Folio Balance Exceptions (Milestone 5 Requirement)
      folio_exceptions = build_folio_balance_exceptions
      exceptions["folio_balance_exceptions"] = folio_exceptions if folio_exceptions.any?

      exceptions
    end

    def hotel_bookings
      @hotel_bookings ||= @hotel.bookings
    end

    def due_out_not_checked_out
      cutoff = (@business_date + 1.day).in_time_zone(@hotel.hotel_time_zone).beginning_of_day
      @due_out_not_checked_out ||= hotel_bookings.where(status: [ "checked_in", "checkout_required" ]).where("check_out < ?", cutoff)
    end

    def review_due_out_bookings
      @review_due_out_bookings ||= hotel_bookings.where(status: "review_due_out")
    end

    def review_no_show_bookings
      @review_no_show_bookings ||= hotel_bookings.where(status: "review_no_show")
    end

    def checked_in_missing_timestamp
      @checked_in_missing_timestamp ||= hotel_bookings.checked_in.where(checked_in_at: nil)
    end

    def completed_missing_timestamp
      @completed_missing_timestamp ||= hotel_bookings.completed.where(checked_out_at: nil)
    end

    def financially_relevant_bookings
      @financially_relevant_bookings ||= hotel_bookings
        .includes(:payment_transactions, :refund_request, :booking_rooms, booking_folio: :folio_transactions)
        .where(
          "(status IN (?) AND check_in::date <= ? AND check_out::date >= ?) OR (status = ? AND check_in::date = ?)",
          %w[checked_in review_due_out checkout_required completed], @business_date, @business_date, "no_show", @business_date
        )
        .to_a
    end

    def missing_folio_bookings
      @missing_folio_bookings ||= financially_relevant_bookings.select do |booking|
        booking.booking_folio.blank? && requires_accounting_folio?(booking)
      end
    end

    def requires_accounting_folio?(booking)
      return false if booking.status.in?(%w[cancelled no_show])

      true
    end

    def nightly_charge_bookings
      @nightly_charge_bookings ||= hotel_bookings
        .includes(:booking_rooms, booking_folio: :folio_transactions)
        .checked_in
        .where("check_in::date <= ? AND check_out::date > ?", @business_date, @business_date)
        .to_a
    end

    def missing_nightly_charge_bookings
      @missing_nightly_charge_bookings ||= nightly_charge_bookings.select do |booking|
        folio = booking.booking_folio
        next false unless folio

        missing_nightly_accommodation_charge?(booking, folio) || missing_nightly_tax_charge?(booking, folio)
      end
    end

    def outstanding_balance_bookings
      @outstanding_balance_bookings ||= financially_relevant_bookings.select do |booking|
        next false unless booking.booking_folio
        next false if booking.status == "no_show"
        next false unless booking.check_out.to_date == @business_date || booking.status == "completed"

        folio_outstanding_balance(booking.booking_folio) != 0.to_d
      end
    end

    def unsynced_captured_payment_transactions
      @unsynced_captured_payment_transactions ||= financially_relevant_bookings.flat_map do |booking|
        next [] unless booking.booking_folio

        booking.payment_transactions.select do |payment_transaction|
          payment_transaction.status == "captured" && !folio_payment_synced?(booking.booking_folio, payment_transaction)
        end
      end
    end

    def unsynced_completed_refund_requests
      @unsynced_completed_refund_requests ||= financially_relevant_bookings.filter_map do |booking|
        refund_request = booking.refund_request
        next unless booking.booking_folio && refund_request&.completed?

        refund_request unless folio_refund_synced?(booking.booking_folio, refund_request)
      end
    end

    def open_housekeeping_requests
      @open_housekeeping_requests ||= HousekeepingRequest.active
        .joins(:booking)
        .where(bookings: { hotel_id: @hotel.id })
        .where.not(status: %w[completed cancelled])
    end

    def open_complaint_requests
      @open_complaint_requests ||= ComplaintRequest.active
        .joins(:booking)
        .where(bookings: { hotel_id: @hotel.id })
        .where.not(status: %w[resolved cancelled])
    end

    def build_folio_balance_exceptions
      # Find in-house guests with unusual balances
      in_house_bookings = hotel_bookings.checked_in.includes(booking_folio: :folio_transactions)

      in_house_bookings.filter_map do |booking|
        next unless booking.booking_folio
        balance = folio_outstanding_balance(booking.booking_folio)

        # We flag large outstanding balances (e.g. > 1000) or large credits (e.g. < -100)
        # These thresholds could eventually be hotel-configurable.
        if balance > 1000.to_d || balance < -100.to_d
          {
            "booking_id" => booking.id,
            "confirmation_token" => booking.confirmation_token,
            "guest_name" => booking.guest_name,
            "status" => booking.status,
            "balance" => balance.to_f,
            "reason" => balance > 0 ? "Large outstanding balance" : "Large credit balance"
          }
        end
      end
    end

    def payment_status_counts
      hotel_bookings.group(:payment_status).count.transform_keys(&:to_s)
    end

    def missing_nightly_accommodation_charge?(booking, folio)
      expected_total = booking.booking_rooms.to_a.sum { |room| nightly_room_amount(room, @business_date) }
      return false if expected_total.zero?

      nightly_charge_total(folio, "accommodation") != expected_total
    end

    def missing_nightly_tax_charge?(booking, folio)
      expected_tax_total = tax_postings_for(booking, @business_date).sum { |tax_line| tax_line_amount(tax_line) }
      return false unless expected_tax_total.positive?

      nightly_charge_total(folio, "tax") != expected_tax_total
    end

    def expected_booking_tax_total(booking)
      tax_total = booking.tax_total.to_d
      return tax_total if tax_total.positive?

      booking.tourism_tax_amount.to_d
    end

    def nightly_charge_total(folio, category)
      folio.folio_transactions.to_a.sum do |transaction|
        transaction.transaction_type == "charge" &&
          transaction.category == category &&
          transaction.metadata["posting_source"] == "night_audit" &&
          transaction.metadata["stay_date"] == @business_date.iso8601 ? transaction.amount.to_d : 0.to_d
      end
    end

    def folio_outstanding_balance(folio)
      folio.folio_transactions.to_a.sum do |transaction|
        case transaction.transaction_type
        when "charge" then transaction.amount.to_d
        when "payment" then -transaction.amount.to_d
        when "adjustment" then transaction.amount.to_d
        else 0.to_d
        end
      end
    end

    def folio_payment_synced?(folio, payment_transaction)
      expected_amount = payment_transaction.amount_subunits.to_d / 100.0

      folio.folio_transactions.any? do |transaction|
        transaction.transaction_type == "payment" &&
          transaction.metadata["payment_transaction_id"].to_s == payment_transaction.id.to_s &&
          transaction.amount.to_d == expected_amount
      end
    end

    def folio_refund_synced?(folio, refund_request)
      expected_amount = -refund_request.refund_amount.to_d

      folio.folio_transactions.any? do |transaction|
        transaction.transaction_type == "payment" &&
          transaction.metadata["refund_request_id"].to_s == refund_request.id.to_s &&
          transaction.amount.to_d == expected_amount
      end
    end

    def serialize_bookings(scope, reason)
      bookings = scope.respond_to?(:order) ? scope.order(:check_out, :id) : scope.sort_by { |booking| [ booking.check_out, booking.id ] }

      bookings.map do |booking|
        {
          "booking_id" => booking.id,
          "confirmation_token" => booking.confirmation_token,
          "guest_name" => booking.guest_name,
          "status" => booking.status,
          "check_in" => booking.check_in,
          "check_out" => booking.check_out,
          "room_numbers" => booking.room_numbers.presence,
          "reason" => reason
        }
      end
    end

    def serialize_payment_transactions(payment_transactions, reason)
      payment_transactions.sort_by(&:id).map do |payment_transaction|
        booking = payment_transaction.booking

        {
          "payment_transaction_id" => payment_transaction.id,
          "booking_id" => booking.id,
          "confirmation_token" => booking.confirmation_token,
          "guest_name" => booking.guest_name,
          "amount" => payment_transaction.amount_subunits.to_d / 100.0,
          "gateway" => payment_transaction.gateway,
          "external_reference" => payment_transaction.external_reference,
          "reason" => reason
        }
      end
    end

    def serialize_refund_requests(refund_requests, reason)
      refund_requests.sort_by(&:id).map do |refund_request|
        booking = refund_request.booking

        {
          "refund_request_id" => refund_request.id,
          "booking_id" => booking.id,
          "confirmation_token" => booking.confirmation_token,
          "guest_name" => booking.guest_name,
          "amount" => refund_request.refund_amount,
          "reason" => reason
        }
      end
    end

    def serialize_requests(scope, details_method, reason)
      scope.order(:requested_at, :id).map do |request|
        booking = request.booking
        {
          "request_id" => request.id,
          "booking_id" => booking.id,
          "confirmation_token" => booking.confirmation_token,
          "guest_name" => booking.guest_name,
          "status" => request.status,
          "details" => request.public_send(details_method),
          "reason" => reason
        }
      end
    end
  end
end
