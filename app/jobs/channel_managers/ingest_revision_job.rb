module ChannelManagers
  class IngestRevisionJob < ApplicationJob
    queue_as :default
    retry_on Channex::Client::RetryableRequestError, wait: :exponentially_longer, attempts: 8

    def perform(hotel_id, revision_id)
      hotel = Hotel.find(hotel_id)
      client = Channex::Client.new

      Rails.logger.info("Channel Manager: Ingesting revision #{revision_id} for hotel #{hotel.name}")

      # Pull full revision data
      response = client.get("/booking_revisions/#{revision_id}")
      if response[:error] || response["error"]
        if response[:retryable] || response["retryable"]
          raise Channex::Client::RetryableRequestError, "Ingest revision retryable failure: #{response[:details] || response['details'] || response}"
        end

        Rails.logger.error("Channel Manager Revision Fetch Failed for ID #{revision_id}: #{response}")
        return
      end

      return unless response["data"]

      adapter = ChannelManagers::SyncOrchestrator.adapter_for(hotel)
      booking_data = adapter.ingest_booking(payload: response, require_property_binding: true)

      result = ChannelManagers::IngestBookingService.new(booking_data: booking_data).call

      # Settlement persistence is intentionally separate from booking/folio
      # ingestion. An unresolved source is operator attention, not a reason to
      # mark a booking paid or to block the booking revision acknowledgement.
      if result.success? && booking_data[:settlement].present?
        settlement_result = ChannelManagers::PersistSettlement.new(
          hotel: hotel,
          settlement_data: booking_data[:settlement]
        ).call
        retry_required = !settlement_result.success?
        if retry_required
          Rails.logger.warn(
            "Channel Manager settlement not persisted for revision #{revision_id}: #{settlement_result.message}"
          )
        end

        if settlement_result.success? && settlement_result.settlement.present?
          application_result = apply_settlement(result, settlement_result.settlement)
          retry_required = !application_result.success?
          if retry_required
            Rails.logger.warn(
              "Channel Manager settlement not applied for revision #{revision_id}: #{application_result.error}"
            )
          end
        end

        if retry_required
          ChannelManagers::ReconcileSettlementJob.perform_later(hotel.id, booking_data[:settlement].to_h)
        end
      end

      if result.success?
        Rails.logger.info("Channel Manager: Successfully ingested revision #{revision_id}. Acknowledging...")
        # Channex expects acknowledgement on the processed booking revision itself.
        ack_response = client.post("/booking_revisions/#{revision_id}/ack")
        if ack_response[:error] || ack_response["error"]
          if ack_response[:retryable] || ack_response["retryable"]
            raise Channex::Client::RetryableRequestError, "Ack retryable failure: #{ack_response[:details] || ack_response['details'] || ack_response}"
          end

          Rails.logger.error("Channel Manager Ack Failed for ID #{revision_id}: #{ack_response}")
        else
          Rails.logger.info("Channel Manager: Acknowledged revision #{revision_id}")
        end
      else
        Rails.logger.error "Channel Manager Ingestion Failed for ID #{revision_id}: #{result.message}"

        # Blocked on hotel configuration (e.g. a missing exchange rate): the revision
        # stays unacknowledged, so fail loudly instead of dropping it into the log.
        if result.failure_code.present?
          raise ChannelManagers::IngestBookingService::UnprocessableBooking,
            "Revision #{revision_id} for hotel #{hotel.id}: #{result.message}"
        end
      end
    end

    private

    def apply_settlement(result, settlement)
      if result.respond_to?(:bookings) && result.bookings.present?
        ChannelManagers::ApplyOtaSettlement.call_many(
          bookings: result.bookings,
          settlement: settlement
        )
      else
        ChannelManagers::ApplyOtaSettlement.call(
          booking: result.booking,
          settlement: settlement
        )
      end
    end
  end
end
