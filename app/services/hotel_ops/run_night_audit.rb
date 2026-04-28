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

        blocked_details = build_blocked_details
        exceptions = build_exceptions
        summary = build_summary(blocked_details:, exceptions:)

        night_audit.update!(
          status: blocked_details.values.flatten.any? ? "blocked" : "completed",
          completed_at: Time.current,
          summary: summary,
          blocked_details: blocked_details,
          exceptions: exceptions
        )
      end

      Result.new(success?: night_audit.completed?, night_audit: night_audit)
    rescue StandardError => e
      night_audit = persist_failure(night_audit)
      Result.new(success?: false, night_audit: night_audit, error: e.message)
    end

    private

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
        "completed_missing_timestamp" => serialize_bookings(completed_missing_timestamp, "Completed booking is missing check-out timestamp")
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

    def serialize_bookings(scope, reason)
      scope.order(:check_out, :id).map do |booking|
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

    def persist_failure(night_audit)
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

      failed_audit
    end
  end
end
