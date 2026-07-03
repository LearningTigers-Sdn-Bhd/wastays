# frozen_string_literal: true

require "ostruct"

module GroupDeposits
  class Receive
    def self.call(group_booking:, amount:, currency:, payment_method:, received_by: nil, external_reference: nil, hotel_corporate_account: nil, metadata: {})
      new(group_booking: group_booking, amount: amount, currency: currency, payment_method: payment_method,
        received_by: received_by, external_reference: external_reference,
        hotel_corporate_account: hotel_corporate_account, metadata: metadata).call
    end

    def initialize(group_booking:, **attributes)
      @group_booking = group_booking
      @attributes = attributes
    end

    def call
      deposit = @group_booking.group_deposits.create!(
        @attributes.merge(hotel: @group_booking.hotel, received_at: Time.current, status: "received")
      )
      OpenStruct.new(success?: true, deposit: deposit)
    rescue ActiveRecord::RecordInvalid => e
      OpenStruct.new(success?: false, error: e.record.errors.full_messages.to_sentence, deposit: nil)
    end
  end
end
