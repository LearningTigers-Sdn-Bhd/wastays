# frozen_string_literal: true

require "ostruct"

module Deposits
  class ReleaseHeldDeposits
    def self.call(booking:, user:, released_at:, method:, reference: nil)
      new(
        booking: booking,
        user: user,
        released_at: released_at,
        method: method,
        reference: reference
      ).call
    end

    def initialize(booking:, user:, released_at:, method:, reference: nil)
      @booking = booking
      @user = user
      @released_at = normalize_timestamp(released_at)
      @method = method.to_s.presence || "cash"
      @reference = reference.to_s.strip.presence
    end

    def call
      return failure("Security deposit release method is not supported.") unless Checkouts::PaymentMethods.valid?(@method)

      released_deposits = []

      Deposit.transaction do
        @booking.deposits.where(status: "held").lock.each do |deposit|
          deposit.update!(
            status: "released",
            released_at: @released_at,
            metadata: deposit.metadata.to_h.merge(
              "released_by_user_id" => @user&.id,
              "release_method" => @method,
              "release_reference" => @reference,
              "source" => "checkout"
            )
          )
          released_deposits << deposit
        end

        @booking.update!(deposit_status: "released") if released_deposits.any?
      end

      success(released_deposits)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def normalize_timestamp(value)
      return value.in_time_zone if value.respond_to?(:in_time_zone)

      Time.zone.parse(value.to_s)
    end

    def success(deposits)
      OpenStruct.new(
        success?: true,
        deposits: deposits,
        deposit_ids: deposits.map(&:id),
        total: deposits.sum { |deposit| deposit.amount.to_d },
        method: @method,
        reference: @reference,
        released_at: @released_at
      )
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
