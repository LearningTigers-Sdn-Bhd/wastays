# frozen_string_literal: true

module Bookings
  # Reverse-solves the room amount (tax-exclusive) that, once BuildFinancialSnapshot
  # applies the hotel's own room-revenue tax rules on top of it, produces a chosen
  # final total — the StayFlexi-style "edit the total, taxes come out on their own"
  # entry point. Treats BuildFinancialSnapshot as a black box and corrects toward the
  # target by fixed-point iteration rather than re-deriving its tax rules, so it stays
  # correct across any mix of percentage and flat room-revenue taxes without having
  # to know which ones are configured.
  #
  # Converges fast because the map is affine except for cent-level rounding noise:
  # each correction shrinks the remaining error by roughly the tax rate (a 6% SST
  # leaves ~6% of the error after one pass), so a handful of iterations is enough
  # for any tax rate under 100%.
  class SolveRoomTotalForFinalAmount
    MAX_ITERATIONS = 6
    TOLERANCE = 0.01

    def initialize(hotel:, room_type:, rate_plan:, check_in:, check_out:, guest_country:, target_total:, adults: nil, children: nil)
      @hotel = hotel
      @room_type = room_type
      @rate_plan = rate_plan
      @check_in = check_in
      @check_out = check_out
      @guest_country = guest_country
      @target_total = target_total.to_d
      @adults = adults
      @children = children
    end

    def call
      candidate = @target_total
      snapshot = nil

      MAX_ITERATIONS.times do
        snapshot = build_snapshot(candidate)
        diff = @target_total - total_for(snapshot)
        break if diff.abs <= TOLERANCE

        candidate = [ candidate + diff, 0.to_d ].max
      end

      snapshot
    end

    private

    def build_snapshot(room_total)
      # A room total of exactly 0 skips every room-revenue tax rule rather than
      # charging none of them at zero rate — BuildFinancialSnapshot only evaluates
      # a date's rules once its basis amount is positive. A cent keeps the same
      # rule set in play as the iteration approaches zero.
      BuildFinancialSnapshot.new(
        hotel: @hotel, room_type: @room_type, rate_plan: @rate_plan,
        check_in: @check_in, check_out: @check_out, guest_country: @guest_country,
        manual_total_amount: room_total.zero? ? 0.01 : room_total,
        adults: @adults, children: @children
      ).call
    end

    def total_for(snapshot)
      snapshot.room_total + Booking.non_tourism_tax_total_for(snapshot.tax_lines)
    end
  end
end
