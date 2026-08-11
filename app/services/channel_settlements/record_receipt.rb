# frozen_string_literal: true

module ChannelSettlements
  class RecordReceipt
    Result = Data.define(:success?, :receipt, :form)

    def self.call(hotel:, user:, attributes:, allocations:)
      new(hotel:, user:, attributes:, allocations:).call
    end

    def initialize(hotel:, user:, attributes:, allocations:)
      @hotel = hotel
      @user = user
      safe_attributes = attributes.respond_to?(:to_h) ? attributes.to_h : attributes
      safe_allocations = allocations.respond_to?(:to_unsafe_h) ? allocations.to_unsafe_h : allocations.to_h
      @form = HotelPortal::ChannelSettlementReceiptForm.new(safe_attributes.merge(allocations: safe_allocations))
    end

    def call
      @form.valid?
      validate_references
      return failure unless @form.errors.empty?

      receipt = nil
      ActiveRecord::Base.transaction do
        selected_allocations.each(&:lock!)
        validate_allocation_rows
        raise ActiveRecord::Rollback unless @form.errors.empty?

        receipt = @hotel.channel_settlement_receipts.create!(receipt_attributes)
        allocation_rows.each do |row|
          receipt.channel_settlement_receipt_allocations.create!(
            channel_settlement_allocation: allocations_by_id.fetch(row[:id]),
            amount: row[:amount],
            currency: @form.currency
          )
        end
        refresh_settlement_statuses!
      end

      receipt ? Result.new(true, receipt, @form) : failure
    rescue ActiveRecord::RecordInvalid => error
      @form.errors.add(:base, error.record.errors.full_messages.to_sentence)
      failure
    rescue ActiveRecord::RecordNotUnique
      @form.errors.add(:external_reference, "has already been recorded for this hotel")
      failure
    end

    private

    def validate_references
      unless booking_source&.kind == "ota"
        @form.errors.add(:booking_source_id, "must be an OTA booking source for this hotel")
      end
      @form.errors.add(:hotel_payment_method_id, "must belong to this hotel") unless payment_method
    end

    def validate_allocation_rows
      if allocation_rows.empty?
        @form.errors.add(:allocations, "must include at least one settlement")
        return
      end
      if allocation_rows.sum { |row| row[:amount] } != @form.amount.to_d
        @form.errors.add(:allocations, "total must equal the receipt amount")
      end

      allocation_rows.each do |row|
        allocation = allocations_by_id[row[:id]]
        if allocation.blank?
          @form.errors.add(:allocations, "include an unavailable settlement")
        elsif row[:amount] <= 0
          @form.errors.add(:allocations, "must be greater than zero")
        end
      end
    end

    def receipt_attributes
      {
        booking_source: booking_source,
        hotel_payment_method: payment_method,
        recorded_by: @user,
        settlement_method: @form.settlement_method,
        amount: @form.amount,
        currency: @form.currency,
        received_at: @form.received_at,
        external_reference: @form.external_reference.to_s.strip.presence,
        notes: @form.notes.to_s.strip.presence
      }
    end

    def booking_source
      @booking_source ||= BookingSource.where(
        id: @hotel.channel_settlements.where(collection_by: "ota").select(:booking_source_id)
      ).find_by(id: @form.booking_source_id)
    end

    def payment_method
      @payment_method ||= @hotel.hotel_payment_methods.active.find_by(id: @form.hotel_payment_method_id)
    end

    def allocation_rows
      @allocation_rows ||= normalized_allocations.filter_map do |id, amount|
        next if amount.blank?
        { id: id.to_i, amount: amount.to_d }
      end
    end

    def normalized_allocations
      values = @form.allocations
      values = values.to_unsafe_h if values.respond_to?(:to_unsafe_h)
      values.to_h
    end

    def selected_allocations
      @selected_allocations ||= @hotel.channel_settlement_allocations
        .joins(:channel_settlement)
        .where(id: allocation_rows.map { |row| row[:id] })
        .where(channel_settlements: { booking_source_id: @form.booking_source_id, currency: @form.currency, collection_by: "ota" })
        .includes(:channel_settlement, :channel_settlement_receipt_allocations)
        .to_a
    end

    def allocations_by_id
      @allocations_by_id ||= selected_allocations.index_by(&:id)
    end

    def remaining_amount(allocation)
      allocation.expected_net_amount.to_d - allocation.channel_settlement_receipt_allocations.sum(&:amount).to_d
    end

    def refresh_settlement_statuses!
      selected_allocations.map(&:channel_settlement).uniq.each do |settlement|
        received = settlement.channel_settlement_allocations.sum do |allocation|
          allocation.channel_settlement_receipt_allocations.reload.sum(:amount)
        end
        status = if received > settlement.expected_net_amount.to_d
          "overpaid"
        elsif received == settlement.expected_net_amount.to_d
          "received"
        elsif received.positive?
          "partially_received"
        else
          settlement.status
        end
        settlement.update!(status:) if status != settlement.status
      end
    end

    def failure
      Result.new(false, nil, @form)
    end
  end
end
