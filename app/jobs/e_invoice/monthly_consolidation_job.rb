# frozen_string_literal: true

module EInvoice
  class MonthlyConsolidationJob < ApplicationJob
    queue_as :default

    HIGH_VALUE_THRESHOLD = 10_000

    # Consolidation must be submitted within 7 days after month end
    DAYS_AFTER_MONTH_END_FOR_CONSOLIDATION = 7

    # LHDN caps document size, so a month is split across documents rather than
    # sent as one oversized payload.
    MAX_BOOKINGS_PER_DOCUMENT = 100

    retry_on MyInvois::Client::ApiError, wait: :polynomially_longer, attempts: 3

    def perform(reference_date = Date.current)
      last_month = reference_date.prev_month.beginning_of_month
      month_end = last_month.end_of_month
      cutoff_date = month_end + DAYS_AFTER_MONTH_END_FOR_CONSOLIDATION.days

      # Only run within the 7-day window after month end
      return if reference_date > cutoff_date
      return if reference_date < month_end + 1.day

      batch_id = SecureRandom.uuid

      Hotel.joins(:e_invoice_setting).where(e_invoice_settings: { enabled: true }).find_each do |hotel|
        process_hotel(hotel, last_month, batch_id)
      end
    end

    private

    def process_hotel(hotel, month_start, batch_id)
      pending_submissions = EInvoiceSubmission
        .where(hotel: hotel)
        .where(status: "pending", consolidated: true, requested_by_guest: false)
        .with_payment_concluded_in_month(month_start, month_start.end_of_month)
        .includes(booking: :booking_rooms)
        .references(:booking, :hotel)

      return if pending_submissions.empty?

      pending_submissions.group_by(&:document_scenario).each do |document_scenario, scenario_submissions|
        process_scenario_batch(hotel, month_start, batch_id, document_scenario, scenario_submissions)
      end
    end

    def process_scenario_batch(hotel, month_start, batch_id, document_scenario, scenario_submissions)
      low_value_bookings = scenario_submissions.map(&:booking).uniq.select do |booking|
        booking.total_amount.to_d < HIGH_VALUE_THRESHOLD
      end

      return if low_value_bookings.empty?

      # One document per slice. A whole month of a busy property in a single
      # document runs past LHDN's per-document size limit, and a rejection
      # there would take the entire month with it.
      low_value_bookings.each_slice(MAX_BOOKINGS_PER_DOCUMENT) do |slice|
        submit_consolidated_slice(hotel, month_start, batch_id, document_scenario, scenario_submissions, slice)
      end
    end

    def submit_consolidated_slice(hotel, month_start, batch_id, document_scenario, scenario_submissions, low_value_bookings)
      context = EInvoice::SubmissionContext.for(low_value_bookings.first, document_scenario: document_scenario)
      builder = EInvoice::ConsolidatedBatchBuilder.new(hotel: hotel, context: context)
      doc = builder.build_for_bookings(low_value_bookings, month_start: month_start)

      slice_ids = scenario_submissions.select { |s| low_value_bookings.map(&:id).include?(s.booking_id) }.map(&:id)
      batch_scope = EInvoiceSubmission.where(id: slice_ids)

      begin
        client = MyInvois::ClientFactory.build(
          mode: context.submission_mode.to_sym,
          represented_taxpayer_tin: context.represented_taxpayer_tin
        )
        response = client.submit_documents([ doc ])

        accepted = Array(response.dig("acceptedDocuments")).first
        rejected = Array(response.dig("rejectedDocuments")).first

        if accepted
          batch_scope.where(booking_id: low_value_bookings.map(&:id)).update_all(
            status: "submitted",
            consolidation_batch_id: batch_id,
            internal_id: doc[:codeNumber],
            uuid: accepted["uuid"],
            submission_uid: response["submissionUid"],
            submitted_at: Time.current,
            raw_response: response
          )
        elsif rejected
          error_details = rejected.dig("error", "details") || []
          batch_scope.where(booking_id: low_value_bookings.map(&:id)).update_all(
            status: "invalid",
            consolidation_batch_id: batch_id,
            internal_id: doc[:codeNumber],
            raw_response: response,
            error_details: { rejected: rejected, messages: error_details.map { |e| e["message"] } }
          )
        else
          Rails.logger.error("[MonthlyConsolidation] Unexpected response for hotel #{hotel.id}, scenario #{document_scenario}: #{response.inspect}")
        end
      rescue EInvoice::SubmissionContext::ConfigurationError => e
        batch_scope.update_all(
          status: "invalid",
          error_details: { message: e.message }
        )
      rescue MyInvois::Client::ApiError => e
        # Let a transient fault bubble to retry_on. Marking a whole hotel-month
        # invalid because LHDN was briefly unavailable would need every record
        # re-filed by hand, inside a 7-day statutory window.
        raise if e.transient?

        Rails.logger.error("[MonthlyConsolidation] #{e.class}: #{e.message} for hotel #{hotel.id}, scenario #{document_scenario}")
        batch_scope.where(booking_id: low_value_bookings.map(&:id)).update_all(
          status: "invalid",
          error_details: { message: e.message }
        )
      rescue => e
        Rails.logger.error("[MonthlyConsolidation] #{e.class}: #{e.message} for hotel #{hotel.id}, scenario #{document_scenario}")
        batch_scope.where(booking_id: low_value_bookings.map(&:id)).update_all(
          status: "invalid",
          error_details: { message: e.message }
        )
      end
    end
  end
end
