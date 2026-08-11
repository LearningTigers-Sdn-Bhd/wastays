# frozen_string_literal: true

module ChannelManagers
  class ReconcileSettlementJob < ApplicationJob
    class ReconciliationError < StandardError; end

    queue_as :default
    retry_on ReconciliationError, wait: :polynomially_longer, attempts: 8

    def perform(hotel_id, settlement_data)
      hotel = Hotel.find(hotel_id)
      persistence = ChannelManagers::PersistSettlement.new(
        hotel: hotel,
        settlement_data: settlement_data
      ).call
      raise ReconciliationError, persistence.message unless persistence.success? && persistence.settlement.present?

      settlement = persistence.settlement
      bookings = bookings_for(hotel, settlement.channel_manager_reference)
      raise ReconciliationError, "No ingested booking found for settlement" if bookings.empty?

      result = if bookings.many?
        ChannelManagers::ApplyOtaSettlement.call_many(bookings: bookings, settlement: settlement)
      else
        ChannelManagers::ApplyOtaSettlement.call(booking: bookings.first, settlement: settlement)
      end
      raise ReconciliationError, result.error unless result.success?

      clear_reconciliation_error(settlement)
    rescue ReconciliationError => e
      mark_for_attention(persistence&.settlement, e.message)
      raise
    end

    private

    def bookings_for(hotel, reference)
      group = hotel.group_bookings.find_by(channel_manager_reference: reference)
      return group.bookings.order(:group_position).to_a if group.present?

      hotel.bookings.where(channel_manager_reference: reference).to_a
    end

    def mark_for_attention(settlement, message)
      return if settlement.blank?

      metadata = settlement.metadata.to_h
      metadata["reconciliation_original_status"] ||= settlement.status
      metadata.merge!(
        "reconciliation_error" => message,
        "reconciliation_failed_at" => Time.current.iso8601
      )
      settlement.update_columns(status: "needs_attention", metadata: metadata, updated_at: Time.current)
    end

    def clear_reconciliation_error(settlement)
      metadata = settlement.metadata.to_h
      original_status = metadata.delete("reconciliation_original_status")
      metadata.delete("reconciliation_error")
      metadata.delete("reconciliation_failed_at")
      attributes = { metadata: metadata, updated_at: Time.current }
      attributes[:status] = original_status if original_status.in?(ChannelSettlement::STATUSES)
      settlement.update_columns(attributes)
    end
  end
end
