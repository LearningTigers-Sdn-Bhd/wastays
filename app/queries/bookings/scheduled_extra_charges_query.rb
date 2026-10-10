# frozen_string_literal: true

module Bookings
  # The extra charges a booking has been scheduled for (a jetty fee, say), tax
  # included: what is owed beyond the room total. A charge counts from the day
  # it is scheduled, whether or not night audit has posted it yet; one that was
  # withdrawn (superseded) does not.
  class ScheduledExtraChargesQuery
    Line = Data.define(:name, :amount)

    # Every booking's extra charges in one query, keyed by booking id, for lists.
    def self.totals_for(bookings)
      scope.where(booking_folios: { booking_id: bookings.map(&:id) })
        .group("booking_folios.booking_id").sum(:amount)
        .transform_values(&:to_d)
    end

    def self.scope
      FolioForecastedCharge.joins(:booking_folio).scheduled_extra_charges.where.not(status: "superseded")
    end

    def initialize(booking)
      @booking = booking
    end

    def total
      @total ||= charges.sum { |charge| charge.amount.to_d }
    end

    # One line per extra charge, its tax folded in, in the order they were scheduled.
    def lines
      charges.group_by { |charge| charge.metadata["extra_charge_id"] }.map do |_, group|
        base = group.find { |charge| charge.charge_kind == "extra_charge" }
        Line.new(name: base&.metadata&.dig("transaction_code_name") || "Extra charge", amount: group.sum { |charge| charge.amount.to_d })
      end
    end

    private

    def charges
      @charges ||= self.class.scope.where(booking_folios: { booking_id: @booking.id }).order(:stay_date, :id).to_a
    end
  end
end
