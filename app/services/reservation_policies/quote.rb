# frozen_string_literal: true

module ReservationPolicies
  # What a stay-event policy charges for a given booking.
  #
  # Every amount here is **pre-tax**. Tax is posted separately by
  # Folios::Transactions::PostAttachedTaxes using ROOM's rules, so a quote that
  # bundled tax into the figure would be taxed a second time on the way to the
  # folio.
  #
  # Room amounts come from Folios::Charges::NightlyChargeCalculation — the same
  # per-night snapshot figure no-show already bills — rather than dividing
  # booking.total_amount, which is a tax-inclusive grand total.
  class Quote
    include Folios::Charges::NightlyChargeCalculation

    Result = ApplicationResult.define(:amount, :policy, :basis_amount, :nights, :label)

    def self.call(...) = new(...).call

    def initialize(booking:, policy_type:, business_date: nil)
      @booking = booking
      @policy_type = policy_type.to_s
      @business_date = business_date || booking.hotel.current_business_date
    end

    def call
      return Result.failure("No #{@policy_type.humanize.downcase} policy is configured.") if policy.blank?
      return Result.success(amount: 0.to_d, policy: policy, basis_amount: 0.to_d, nights: 0, label: "Not charged") unless policy.active?

      # A manual policy has no computed amount by design — staff name the figure.
      return Result.success(amount: nil, policy: policy, basis_amount: per_night_amount, nights: stay_nights, label: policy.pricing_label) if policy.manual?

      Result.success(
        amount: amount.round(2),
        policy: policy,
        basis_amount: basis_amount.round(2),
        nights: stay_nights,
        label: policy.pricing_label
      )
    end

    private

    def policy
      return @policy if defined?(@policy)

      ReservationPolicies::EnsureDefaults.call(@booking.hotel)
      @policy = @booking.hotel.hotel_reservation_policies.find_by(policy_type: @policy_type)
    end

    def amount
      return policy.rate_value.to_d if policy.fixed?
      return per_night_amount * policy.whole_nights if policy.nights?

      basis_amount * policy.rate_value.to_d / 100
    end

    def basis_amount
      case policy.percentage_basis
      when "total_stay" then stay_total
      when "remaining_nights" then per_night_amount * remaining_nights
      else per_night_amount
      end
    end

    # Pre-tax room revenue for one night, across every room on the booking.
    def per_night_amount
      @per_night_amount ||= @booking.booking_rooms.sum { |room| nightly_room_amount(room, @business_date) }
    end

    # Pre-tax room revenue for the whole stay.
    def stay_total
      @stay_total ||= @booking.booking_rooms.sum { |room| room.subtotal.to_d }
    end

    def stay_nights
      @stay_nights ||= booking_stay_dates(@booking).length
    end

    def remaining_nights
      @remaining_nights ||= booking_stay_dates(@booking).count { |date| date >= @business_date.to_date }
    end
  end
end
