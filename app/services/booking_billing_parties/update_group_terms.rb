# frozen_string_literal: true

module BookingBillingParties
  class UpdateGroupTerms
    Result = Data.define(:success?, :parties, :errors)
    class UpdateFailed < StandardError; end

    def self.call(party:, actor:, attributes:)
      new(party:, actor:, attributes:).call
    end

    def initialize(party:, actor:, attributes:)
      @party = party
      @actor = actor
      @attributes = attributes
    end

    def call
      return Result.new(false, [], [ "Only account payers can be updated across a group." ]) unless @party.company?
      return Result.new(false, [], [ "This payer is not attached to a group booking." ]) unless @party.booking.group_booking_id?

      parties = []
      ActiveRecord::Base.transaction do
        group = @party.booking.group_booking
        group.lock!
        booking_ids = group.bookings.order(:group_position, :id).lock.pluck(:id)
        parties = BookingBillingParty.active.companies
          .where(booking_id: booking_ids, hotel_corporate_account_id: @party.hotel_corporate_account_id)
          .includes(:billing_terms, :booking)
          .order(:booking_id)
          .lock
          .to_a

        parties.each do |party|
          result = BookingBillingParties::UpdateTerms.call(party:, actor: @actor, attributes: @attributes)
          raise UpdateFailed, result.error unless result.success?
        end
      end

      return Result.new(false, [], [ "Billing terms could not be updated across the group." ]) if parties.empty?

      Result.new(true, parties, [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(false, [], e.record.errors.full_messages)
    rescue UpdateFailed => e
      Result.new(false, [], [ e.message ])
    end
  end
end
