# frozen_string_literal: true

module Billing
  class ResolveBookingAssignment
    Result = Data.define(:assignment, :billing_party, :terms, :source, :errors) do
      def success? = errors.empty?
    end

    def self.call(booking:, charge_category:, on: Date.current)
      new(booking: booking, charge_category: charge_category, on: on).call
    end

    def initialize(booking:, charge_category:, on:)
      @booking = booking
      @charge_category = charge_category.to_s
      @on = on.to_date
    end

    def call
      return guest_result if @charge_category.in?(%w[tourism_tax ttx])

      assignment = @booking.booking_billing_assignments
        .includes(group_billing_arrangement: :hotel_corporate_account)
        .where(charge_category: @charge_category)
        .where("effective_from IS NULL OR effective_from <= ?", @on)
        .where("effective_until IS NULL OR effective_until >= ?", @on)
        .first
      return guest_result unless assignment

      arrangement = assignment.group_billing_arrangement
      return failure(assignment, "Billing arrangement is inactive or outside its validity period.") unless arrangement.status == "active" && arrangement_valid?(arrangement)

      arrangement.payer_type == "company" ? company_result(assignment, arrangement) : guest_result(assignment)
    end

    private

    def arrangement_valid?(arrangement)
      (arrangement.valid_from.blank? || arrangement.valid_from <= @on) &&
        (arrangement.valid_until.blank? || arrangement.valid_until >= @on)
    end

    def guest_result(assignment = nil)
      guest = @booking.booking_guests.find(&:primary?)
      return failure(assignment, "Booking has no primary guest billing party.") unless guest&.booking_billing_party

      party = guest.booking_billing_party
      Result.new(assignment: assignment, billing_party: party, terms: party.billing_terms,
        source: assignment&.local_exception? ? "local" : "group", errors: [])
    end

    def company_result(assignment, arrangement)
      account = arrangement.hotel_corporate_account
      return failure(assignment, "Company & Government Account is inactive.") unless account&.active?
      if arrangement.settlement_type == "city_ledger" && !account.direct_bill_enabled?
        return failure(assignment, "Company & Government Account is not eligible for City Ledger.")
      end

      party = @booking.booking_billing_parties.active.find_by(hotel_corporate_account: account)
      return failure(assignment, "Company billing party has not been ensured for this booking.") unless party

      Result.new(assignment: assignment, billing_party: party, terms: party.billing_terms,
        source: assignment.local_exception? ? "local" : "group", errors: [])
    end

    def failure(assignment, message)
      Result.new(assignment: assignment, billing_party: nil, terms: nil,
        source: assignment&.local_exception? ? "local" : "group", errors: [ message ])
    end
  end
end
