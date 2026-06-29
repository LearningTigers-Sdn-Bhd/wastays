# frozen_string_literal: true

module EInvoice
  class AutoIssueJob < ApplicationJob
    queue_as :default

    HIGH_VALUE_THRESHOLD = 10_000

    def perform(booking_id, requested_by_guest: false)
      booking = Booking.find_by(id: booking_id)
      return unless booking

      hotel = booking.hotel
      return unless booking.payment_concluded?
      return unless hotel.e_invoice_setting&.enabled?

      scenario = booking.direct_hotel_payment? ? "hotel_intermediary_guest_invoice" : "guest_invoice"

      # Case: Guest requests within same month
      if requested_by_guest
        handle_guest_request(booking, hotel, scenario)
        return
      end

      # Case: Automatic processing for low-value bookings.
      # Both WAStays-collected and hotel-direct bookings get consolidated placeholders,
      # and month-end processing will submit them in separate issuer-specific batches.
      if booking.total_amount.to_d < HIGH_VALUE_THRESHOLD
        booking.create_pending_consolidated_submission!
        return
      end

      # Case: High-value booking (>= RM10,000) - create individual submission
      issue_individual_submission(booking, hotel, scenario, requested_by_guest: false)
    end

    private

    def handle_guest_request(booking, hotel, scenario)
      # Check for existing pending individual submission (from earlier guest request)
      existing_individual = booking.e_invoice_submissions.guest_facing
        .where(status: "pending", consolidated: false)
        .first

      if existing_individual
        # Already has a pending individual request - no-op (caller should have checked)
        return
      end

      # Check for existing consolidated placeholder that was not requested by guest
      existing_consolidated = booking.e_invoice_submissions.guest_facing
        .where(status: "pending", consolidated: true, requested_by_guest: false)
        .first

      if existing_consolidated
        # Cancel consolidated placeholder and create individual submission
        existing_consolidated.update!(status: "cancelled", error_details: { converted_to_individual: true })
      end

      issue_individual_submission(booking, hotel, scenario, requested_by_guest: true)
    end

    def issue_individual_submission(booking, hotel, scenario, requested_by_guest:)
      # Check if e-invoice already issued (submitted and valid)
      return if booking.e_invoice_submissions.guest_facing.where(status: %w[submitted valid]).exists?

      submission = booking.e_invoice_submissions.where.not(status: "cancelled").find_or_initialize_by(
        booking_id: booking.id,
        document_scenario: scenario
      )

      # Already has a pending individual submission
      if submission.persisted? && submission.status.in?(%w[pending submitted valid])
        return
      end

      begin
        context = EInvoice::SubmissionContext.for(booking, document_scenario: scenario)
        submission.assign_attributes(
          hotel: hotel,
          document_type: "01",
          submission_mode: context.submission_mode,
          fund_collector: context.fund_collector,
          supplier_name: context.supplier_name,
          supplier_tin: context.supplier_tin,
          represented_taxpayer_tin: context.represented_taxpayer_tin,
          status: "pending",
          consolidated: false,
          requested_by_guest: requested_by_guest,
          requested_at: requested_by_guest ? Time.current : nil,
          payment_concluded_at: booking.payment_concluded_at,
          uuid: nil, long_id: nil, submission_uid: nil,
          submitted_at: nil, validated_at: nil, cancelled_at: nil,
          raw_response: {}, error_details: {}
        )
        submission.save!
      rescue EInvoice::SubmissionContext::ConfigurationError => e
        submission.assign_attributes(
          hotel: hotel, document_type: "01", status: "invalid",
          error_details: { message: e.message }
        )
        submission.save!
        return
      end

      EInvoice::SubmitJob.perform_later(submission.id)
    end
  end
end
