module HotelOps
  class RunNightAudit
    Result = Struct.new(:success?, :night_audit, :error, keyword_init: true)

    def initialize(hotel:, business_date:, performed_by_user:, trigger_mode:, notes: nil)
      @hotel = hotel
      @business_date = business_date.to_date
      @performed_by_user = performed_by_user
      @trigger_mode = trigger_mode
      @notes = notes.to_s.strip.presence
    end

    def call
      night_audit = @hotel.night_audits.find_or_initialize_by(business_date: @business_date)
      return Result.new(success?: false, error: "Night audit has already been completed for this date.", night_audit: night_audit) if night_audit.completed?

      summary = {}
      blocked_details = {}
      exceptions = {}

      ActiveRecord::Base.transaction do
        night_audit.assign_attributes(
          status: "running",
          trigger_mode: @trigger_mode,
          started_at: Time.current,
          completed_at: nil,
          performed_by_user: @performed_by_user,
          notes: @notes,
          force_closed: false
        )
        night_audit.save!

        log_event(night_audit, "process_started", "Night audit process started for business date #{@business_date}")

        Folios::PostNightlyCharges.call(night_audit: night_audit, user: @performed_by_user)

        blocked_details = build_blocked_details
        log_blockers(night_audit, blocked_details)

        exceptions = build_exceptions
        log_exceptions(night_audit, exceptions)

        summary = build_summary(blocked_details:, exceptions:)

        night_audit.update!(
          status: blocked_details.values.flatten.any? ? "blocked" : "completed",
          completed_at: Time.current,
          summary: summary,
          blocked_details: blocked_details,
          exceptions: exceptions
        )

        final_status = night_audit.status
        log_event(night_audit, final_status == "completed" ? "completed" : "blocker_found", "Night audit process finished with status: #{final_status}")
      end

      Result.new(success?: night_audit.completed?, night_audit: night_audit)
    rescue StandardError => e
      night_audit = persist_failure(night_audit, e.message)
      Result.new(success?: false, night_audit: night_audit, error: e.message)
    end

    private

    def log_event(night_audit, action_type, message, metadata = {})
      night_audit.night_audit_logs.create!(
        hotel: @hotel,
        user: @performed_by_user,
        action_type: action_type,
        message: message,
        metadata: metadata
      )
    end

    def log_blockers(night_audit, blocked_details)
      blocked_details.each do |type, items|
        next if items.empty?

        log_event(night_audit, "blocker_found", "Found #{items.count} blockers of type: #{type.humanize}", { type: type, count: items.count, items: items })
      end
    end

    def log_exceptions(night_audit, exceptions)
      exceptions.each do |type, items|
        next if items.empty?

        log_event(night_audit, "exception_found", "Found #{items.count} exceptions of type: #{type.humanize}", { type: type, count: items.count, items: items })
      end
    end

    def build_summary(blocked_details:, exceptions:)
      {
        "arrivals_count" => hotel_bookings.where(check_in: @business_date).count,
        "due_out_count" => hotel_bookings.where(check_out: @business_date).count,
        "checked_out_count" => hotel_bookings.completed.where(checked_out_at: @business_date.all_day).count,
        "in_house_count" => hotel_bookings.checked_in.where("check_in <= ? AND check_out >= ?", @business_date, @business_date).count,
        "warning_count" => exceptions.values.flatten.count,
        "blocker_count" => blocked_details.values.flatten.count,
        "payment_status_counts" => payment_status_counts
      }
    end

    def build_blocked_details
      {
        "due_out_not_checked_out" => serialize_bookings(due_out_not_checked_out, "Due out today but still not checked out"),
        "checked_in_missing_timestamp" => serialize_bookings(checked_in_missing_timestamp, "Checked-in booking is missing check-in timestamp"),
        "completed_missing_timestamp" => serialize_bookings(completed_missing_timestamp, "Completed booking is missing check-out timestamp"),
        "missing_folio" => serialize_bookings(missing_folio_bookings, "Booking requires a folio before night audit can close"),
        "missing_nightly_charges" => serialize_bookings(missing_nightly_charge_bookings, "Booking folio is missing required nightly charges"),
        "outstanding_folio_balance" => serialize_bookings(outstanding_balance_bookings, "Booking has outstanding folio balance at checkout"),
        "captured_payment_not_synced" => serialize_payment_transactions(unsynced_captured_payment_transactions, "Captured payment is not synced to the booking folio"),
        "refund_not_synced" => serialize_refund_requests(unsynced_completed_refund_requests, "Completed refund is not synced to the booking folio")
      }
    end

    def build_exceptions
      {
        "open_housekeeping_requests" => serialize_requests(open_housekeeping_requests, :request_details, "Housekeeping request still open"),
        "open_complaint_requests" => serialize_requests(open_complaint_requests, :complaint_details, "Complaint request still open")
      }
    end

    def hotel_bookings
      @hotel_bookings ||= @hotel.bookings
    end

    def due_out_not_checked_out
      @due_out_not_checked_out ||= hotel_bookings.where(check_out: @business_date).where.not(status: "completed")
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
        .where(status: %w[checked_in completed])
        .where("check_in <= ? AND check_out >= ?", @business_date, @business_date)
        .to_a
    end

    def missing_folio_bookings
      @missing_folio_bookings ||= financially_relevant_bookings.select { |booking| booking.booking_folio.blank? }
    end

    def nightly_charge_bookings
      @nightly_charge_bookings ||= hotel_bookings
        .includes(:booking_rooms, booking_folio: :folio_transactions)
        .checked_in
        .where("check_in <= ? AND check_out > ?", @business_date, @business_date)
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
        next false unless booking.check_out == @business_date || booking.status == "completed"

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

    def payment_status_counts
      hotel_bookings.group(:payment_status).count.transform_keys(&:to_s)
    end

    def missing_nightly_accommodation_charge?(booking, folio)
      expected_total = booking.booking_rooms.to_a.sum { |room| nightly_amount(room.subtotal, booking) }
      return false if expected_total.zero?

      nightly_charge_total(folio, "accommodation") != expected_total
    end

    def missing_nightly_tax_charge?(booking, folio)
      expected_tax_total = nightly_amount(expected_booking_tax_total(booking), booking)
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

    def nightly_amount(total_amount, booking)
      nights = (booking.check_out.to_date - booking.check_in.to_date).to_i
      return 0.to_d unless nights.positive?

      per_night = (total_amount.to_d / nights).round(2)
      return per_night unless @business_date == booking.check_out.to_date - 1.day

      total_amount.to_d - (per_night * (nights - 1))
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

    def persist_failure(night_audit, error_message)
      failed_audit = night_audit.presence || @hotel.night_audits.find_or_initialize_by(business_date: @business_date)
      failed_audit.assign_attributes(
        status: "failed",
        trigger_mode: @trigger_mode,
        performed_by_user: @performed_by_user,
        completed_at: Time.current,
        notes: @notes,
        force_closed: false
      )
      failed_audit.started_at ||= Time.current
      failed_audit.summary ||= {}
      failed_audit.blocked_details ||= {}
      failed_audit.exceptions ||= {}
      failed_audit.save!(validate: false)

      log_event(failed_audit, "failed", "Night audit failed: #{error_message}", { error: error_message })

      failed_audit
    end
  end
end
