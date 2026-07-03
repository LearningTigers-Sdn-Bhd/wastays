# frozen_string_literal: true

require "ostruct"

module Billing
  class ApplyGroupArrangement
    def self.call(arrangement:, bookings:, charge_categories:, actor: nil, local_exception: false, replace_local_exceptions: false)
      new(arrangement: arrangement, bookings: bookings, charge_categories: charge_categories, actor: actor,
        local_exception: local_exception, replace_local_exceptions: replace_local_exceptions).call
    end

    def initialize(arrangement:, bookings:, charge_categories:, actor: nil, local_exception: false, replace_local_exceptions: false)
      @arrangement = arrangement
      @bookings = Array(bookings).uniq
      @charge_categories = Array(charge_categories).map(&:to_s).uniq
      @actor = actor
      @local_exception = local_exception
      @replace_local_exceptions = replace_local_exceptions
    end

    def call
      return failure("Select at least one booking and charge category.") if @bookings.empty? || @charge_categories.empty?
      return failure("Every booking must belong to the arrangement's group.") unless @bookings.all? { |booking| booking.group_booking_id == @arrangement.group_booking_id }

      assignments = []
      skipped = []
      BookingBillingAssignment.transaction do
        @bookings.each do |booking|
          @charge_categories.each do |category|
            assignment = booking.booking_billing_assignments.find_or_initialize_by(charge_category: category)
            if assignment.persisted? && assignment.local_exception? && !@local_exception && !@replace_local_exceptions
              skipped << assignment
              next
            end
            assignment.assign_attributes(group_billing_arrangement: @arrangement, local_exception: @local_exception)
            assignment.save!
            assignments << assignment
          end
          record_audit!(booking, assignments.select { |candidate| candidate.booking_id == booking.id })
          if @arrangement.payer_type == "company"
            folio_result = Billing::EnsureCorporateFolio.call(booking: booking, arrangement: @arrangement, actor: @actor)
            raise folio_result.error unless folio_result.success?
          end
        end
      end

      OpenStruct.new(success?: true, assignments: assignments, skipped_assignments: skipped)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      failure(e.message)
    end

    private

    def record_audit!(booking, assignments)
      return if assignments.empty?

      BookingAuditLog.create!(hotel: booking.hotel, auditable: booking, user: @actor,
        action_type: @local_exception ? "billing_local_exception_applied" : "group_billing_applied",
        category: "financial", source: "booking_control_panel", occurred_at: Time.current,
        new_value: { arrangement_id: @arrangement.id, categories: assignments.map(&:charge_category) })
    end

    def failure(message)
      OpenStruct.new(success?: false, error: message, assignments: [])
    end
  end
end
