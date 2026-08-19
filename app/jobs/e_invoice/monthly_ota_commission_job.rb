# frozen_string_literal: true

module EInvoice
  # Files one self-billed e-invoice per hotel, per OTA, per month for the
  # commission that OTA kept. The OTAs are overseas companies, so LHDN never
  # receives an e-invoice from them; the hotel must self-bill to deduct the
  # expense as an importation of services.
  class MonthlyOtaCommissionJob < ApplicationJob
    queue_as :default

    retry_on MyInvois::Client::ApiError, wait: :polynomially_longer, attempts: 3

    def perform(reference_date = Date.current)
      period_start = reference_date.to_date.prev_month.beginning_of_month

      Hotel.joins(:e_invoice_setting).where(e_invoice_settings: { enabled: true }).find_each do |hotel|
        next unless hotel.e_invoice_setting.covers?(period_start.end_of_month)

        commission_by_source(hotel, period_start).each do |source_key, (amount, count)|
          file_commission(hotel, source_key, period_start, amount, count)
        end
      end
    end

    private

    # Commission is what the guest paid less what the hotel kept, whoever
    # collected it: on a prepaid stay the OTA withholds it, on a pay-at-hotel
    # stay the hotel is invoiced for it later. Either way it is a service the
    # hotel bought from the OTA in that month.
    def commission_by_source(hotel, period_start)
      bookings = hotel.bookings
        .where(checked_out_at: period_start.beginning_of_day..period_start.end_of_month.end_of_day)
        .where.not(net_amount: nil)

      bookings.each_with_object({}) do |booking, totals|
        next unless booking.ota_booking?

        commission = booking.ota_commission_amount
        next unless commission.positive?

        amount, count = totals.fetch(booking.source, [ 0.to_d, 0 ])
        totals[booking.source] = [ amount + commission, count + 1 ]
      end
    end

    def file_commission(hotel, source_key, period_start, amount, count)
      source = BookingSource.find_by_source(source_key)
      return unless source&.self_bill_commission?

      submission = EInvoiceSubmission.find_or_initialize_by(
        hotel: hotel,
        document_scenario: "ota_commission_self_billed",
        ota_source_key: source.key,
        period_start: period_start
      )
      # Already filed and accepted; nothing to redo.
      return if submission.persisted? && submission.status.in?(%w[submitted valid])

      builder = EInvoice::OtaCommissionSelfBilledBuilder.new(
        hotel: hotel,
        source: source,
        period_start: period_start,
        amount: amount,
        booking_count: count
      )
      doc = builder.build

      submission.assign_attributes(
        document_type: "11",
        submission_mode: "taxpayer",
        fund_collector: "hotel",
        supplier_name: source.legal_name.presence || source.label,
        supplier_tin: EInvoice::OtaCommissionSelfBilledBuilder::FOREIGN_SUPPLIER_TIN,
        internal_id: builder.internal_id,
        status: "pending"
      )
      submission.save!

      client = MyInvois::ClientFactory.build(mode: :taxpayer, setting: hotel.e_invoice_setting)
      response = client.submit_documents([ doc ])

      accepted = Array(response["acceptedDocuments"]).first
      rejected = Array(response["rejectedDocuments"]).first

      if accepted
        submission.update!(
          status: "submitted",
          uuid: accepted["uuid"],
          submission_uid: response["submissionUid"],
          submitted_at: Time.current,
          raw_response: response
        )
      elsif rejected
        submission.update!(
          status: "invalid",
          raw_response: response,
          error_details: { rejected: rejected }
        )
      end
    rescue MyInvois::Client::ApiError => e
      raise if e.transient?

      Rails.logger.error("[OtaCommission] #{e.class}: #{e.message} for hotel #{hotel.id}, source #{source_key}")
      submission&.update(status: "invalid", error_details: { message: e.message })
    rescue StandardError => e
      Rails.logger.error("[OtaCommission] #{e.class}: #{e.message} for hotel #{hotel.id}, source #{source_key}")
      submission&.update(status: "invalid", error_details: { message: e.message })
    end
  end
end
