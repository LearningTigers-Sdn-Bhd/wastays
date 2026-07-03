# frozen_string_literal: true

require "ostruct"

module Billing
  class SaveGroupArrangement
    ATTRIBUTES = %i[name payer_type hotel_corporate_account_id settlement_type preferred_payment_method
      billing_reference purchase_order_reference authorization_reference valid_from valid_until status coverage].freeze

    def self.call(group_booking:, arrangement: nil, actor:, attributes:)
      new(group_booking: group_booking, arrangement: arrangement, actor: actor, attributes: attributes).call
    end

    def initialize(group_booking:, arrangement:, actor:, attributes:)
      @group = group_booking
      @arrangement = arrangement || group_booking.group_billing_arrangements.build
      @actor = actor
      @attributes = attributes.to_h.with_indifferent_access
    end

    def call
      previous = @arrangement.persisted? ? @arrangement.attributes.slice(*ATTRIBUTES.map(&:to_s)) : {}
      @arrangement.assign_attributes(@attributes.slice(*ATTRIBUTES))
      @arrangement.hotel = @group.hotel
      @arrangement.coverage = normalized_coverage
      @arrangement.save!
      audit_children!(previous)
      OpenStruct.new(success?: true, arrangement: @arrangement, error: nil)
    rescue ActiveRecord::RecordInvalid => e
      OpenStruct.new(success?: false, arrangement: e.record, error: e.record.errors.full_messages.to_sentence)
    end

    private

    def normalized_coverage
      Array(@attributes[:charge_categories]).presence&.index_with(true) || @attributes[:coverage].to_h
    end

    def audit_children!(previous)
      @group.bookings.find_each do |booking|
        BookingAuditLog.create!(hotel: @group.hotel, auditable: booking, user: @actor,
          action_type: @arrangement.previously_new_record? ? "group_billing_arrangement_created" : "group_billing_arrangement_updated",
          category: "financial", source: "booking_control_panel", occurred_at: Time.current,
          old_value: previous, new_value: @arrangement.attributes.slice(*ATTRIBUTES.map(&:to_s)))
      end
    end
  end
end
