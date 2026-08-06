# frozen_string_literal: true

module Cancellations
  # What cancelling this booking costs, and what goes back to the guest.
  #
  # The tiers store what the hotel *retains*, and the refund is derived from it.
  # Storing both would let a policy keep 30% and refund 50% with nobody able to
  # say where the remaining fifth went.
  #
  # Like ReservationPolicies::Quote, the fee is pre-tax: it posts under CANCEL and
  # picks up ROOM's tax rules on the way to the folio.
  class Quote
    include Folios::Charges::NightlyChargeCalculation

    Result = ApplicationResult.define(:fee_amount, :refund_amount, :amount_paid, :tier, :policy, :base_amount, :days_out)

    def self.call(...) = new(...).call

    def initialize(booking:, business_date: nil)
      @booking = booking
      @business_date = (business_date || booking.hotel.current_business_date).to_date
    end

    def call
      return Result.failure("No cancellation policy is configured.") if policy.blank?
      return no_charge_result unless policy.active?

      fee = [ tier_fee, 0.to_d ].max.round(2)
      Result.success(
        fee_amount: fee,
        refund_amount: [ amount_paid - fee, 0.to_d ].max.round(2),
        amount_paid: amount_paid,
        tier: matched_tier,
        policy: policy,
        base_amount: stay_total,
        days_out: days_out
      )
    end

    private

    def no_charge_result
      Result.success(
        fee_amount: 0.to_d, refund_amount: amount_paid, amount_paid: amount_paid,
        tier: nil, policy: policy, base_amount: stay_total, days_out: days_out
      )
    end

    def policy
      return @policy if defined?(@policy)

      ReservationPolicies::EnsureDefaults.call(@booking.hotel)
      @policy = @booking.hotel.hotel_reservation_policies.includes(:cancellation_tiers).find_by(policy_type: "cancellation")
    end

    # Counted from the hotel's business date, never Time.current — a property that
    # has not yet rolled its business date is still trading on yesterday.
    def days_out
      @days_out ||= (@booking.check_in.to_date - @business_date).to_i
    end

    # The tightest band the guest still qualifies for: the largest threshold that
    # the days remaining still clears. Cancelling inside every band falls through
    # to the policy's own pricing.
    def matched_tier
      return @matched_tier if defined?(@matched_tier)

      @matched_tier = policy.cancellation_tiers
        .select { |tier| days_out >= tier.days_before_arrival }
        .max_by(&:days_before_arrival)
    end

    def tier_fee
      return policy_level_fee if matched_tier.blank?

      compute(matched_tier.pricing_type, matched_tier.rate_value, matched_tier.percentage_basis)
    end

    def policy_level_fee
      return 0.to_d if policy.manual?

      compute(policy.pricing_type, policy.rate_value, policy.percentage_basis)
    end

    def compute(pricing_type, rate_value, percentage_basis)
      rate = rate_value.to_d

      case pricing_type
      when "fixed" then rate
      when "nights" then per_night_amount * rate.to_i
      when "percentage" then basis_amount(percentage_basis) * rate / 100
      else 0.to_d
      end
    end

    def basis_amount(percentage_basis)
      case percentage_basis
      when "first_night" then per_night_amount
      when "remaining_nights" then per_night_amount * remaining_nights
      else stay_total
      end
    end

    def per_night_amount
      @per_night_amount ||= @booking.booking_rooms.sum { |room| nightly_room_amount(room, @business_date) }
    end

    def stay_total
      @stay_total ||= @booking.booking_rooms.sum { |room| room.subtotal.to_d }
    end

    def remaining_nights
      @remaining_nights ||= booking_stay_dates(@booking).count { |date| date >= @business_date }
    end

    # Everything the guest has actually handed over — deposits and folio payments
    # both count, since either can be the thing a refund comes out of. Released,
    # refunded and cancelled deposits are money the hotel no longer holds.
    HELD_DEPOSIT_STATUSES = %w[held available settled].freeze

    def amount_paid
      @amount_paid ||= (held_deposits + folio_payments).round(2)
    end

    def held_deposits
      @booking.deposits.where(status: HELD_DEPOSIT_STATUSES).sum(:amount).to_d
    end

    def folio_payments
      return 0.to_d if @booking.booking_folio.blank?

      @booking.booking_folio.folio_transactions.payments.where(voided_by_transaction_id: nil).sum(:amount).to_d.abs
    end
  end
end
