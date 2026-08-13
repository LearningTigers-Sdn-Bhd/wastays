# frozen_string_literal: true

module HotelPortal
  # What one rate plan charges for a single room category.
  #
  # The form is scoped to one category on purpose. Capacity varies between
  # categories, so a matrix spanning all of them is either ragged or padded to
  # the property's largest room — the old sheet did the first, the bulk dialog
  # does the second. With one category per form, max_adults is known and the
  # fields are exactly as long as the room is deep.
  class RatePlanRoomPricing
    include ActiveModel::Model
    include ActiveModel::Attributes

    PER_ROOM_MODES = %w[manual derived].freeze
    PER_PERSON_MODES = %w[manual derived auto].freeze
    DERIVE_MODES = %w[multiplier offset].freeze

    attribute :rate_mode, :string, default: "manual"
    attribute :default_rate, :decimal
    attribute :derive_mode, :string, default: "multiplier"
    attribute :derive_value, :decimal
    attribute :primary_occupancy, :integer, default: 2
    attribute :increase_by, :decimal, default: 0
    attribute :increase_unit, :string, default: "amount"
    attribute :decrease_by, :decimal, default: 0
    attribute :decrease_unit, :string, default: "amount"

    # room_type and sell mode are context, not user input — they come from the
    # category being priced and from the property, never from the form.
    attr_accessor :room_type
    attr_writer :sells_per_person, :prices

    validate :rate_mode_is_offered
    validate :manual_prices_are_complete, if: -> { manual? && per_person? }
    validate :manual_rate_is_present, if: -> { manual? && !per_person? }
    validate :derive_value_is_present, if: :derived?
    validate :anchor_is_available, if: -> { derived? && per_person? }
    validate :auto_rate_is_present, if: :auto?

    # Accepts either permitted params on the way in or the plain hash that came
    # back out of the session, so the two round-trip through the same door.
    def self.from_h(attrs, room_type:, sells_per_person:)
      attrs = (attrs.respond_to?(:to_h) ? attrs.to_h : {}).deep_stringify_keys
      pricing = new(attrs.except("prices"))
      pricing.room_type = room_type
      pricing.sells_per_person = sells_per_person
      pricing.prices = attrs["prices"]
      pricing
    end

    def self.from_assignment(assignment, room_type:, sells_per_person:)
      return from_h({}, room_type: room_type, sells_per_person: sells_per_person) unless assignment

      attrs = if sells_per_person
        {
          "rate_mode" => "manual",
          "prices" => assignment.occupancy_prices.index_by(&:adults).transform_values(&:price)
        }
      elsif assignment.derives_price?
        {
          "rate_mode" => "derived",
          "derive_mode" => assignment.pricing_mode,
          "derive_value" => assignment.pricing_value
        }
      else
        { "rate_mode" => "manual", "default_rate" => assignment.pricing_value }
      end

      from_h(attrs, room_type: room_type, sells_per_person: sells_per_person)
    end

    def to_h
      attributes.merge("prices" => prices.transform_keys(&:to_s).transform_values(&:to_s))
    end

    def per_person? = !!@sells_per_person
    def manual? = rate_mode == "manual"
    def derived? = rate_mode == "derived"
    def auto? = rate_mode == "auto"

    def available_modes = per_person? ? PER_PERSON_MODES : PER_ROOM_MODES

    def max_adults = [ room_type&.max_adults.to_i, 1 ].max

    def adult_counts = (1..max_adults)

    # Keyed by integer adult count so views and the ladder agree; values stay
    # strings until they are cast, so a half-typed field round-trips intact.
    def prices
      @prices ||= {}
      adult_counts.index_with { |adults| @prices[adults.to_s] || @prices[adults] }
    end

    def price_for(adults) = prices[adults.to_i]

    # The nightly figure at primary occupancy that the ladder steps away from.
    # Auto takes it from the form; Derived reads the category's standard rate
    # and applies the same adjustment a per-room derived plan would.
    def anchor
      return default_rate if auto?
      return unless derived?

      RoomTypeRatePlan.new(pricing_mode: derive_mode, pricing_value: derive_value)
                      .derive_price(room_type&.base_price)
    end

    # The full matrix this form contributes. Empty for a per-room plan, which
    # prices the room once rather than per adult count.
    def occupancy_matrix
      return {} unless per_person?
      return manual_matrix if manual?
      return derived_matrix if derived?

      RatePlans::OccupancyLadder.call(
        anchor: anchor,
        max_adults: max_adults,
        primary_occupancy: primary_occupancy,
        increase_by: increase_by,
        increase_unit: increase_unit,
        decrease_by: decrease_by,
        decrease_unit: decrease_unit
      )
    end

    # Per-person plans always store a complete matrix, so the assignment itself
    # carries no scalar price and stays on "fixed". Per-room plans put the
    # money here: a typed rate, or the rule that derives one from the standard.
    def assignment_attributes
      return { pricing_mode: "fixed", pricing_value: nil } if per_person?
      return { pricing_mode: derive_mode, pricing_value: derive_value } if derived?

      { pricing_mode: "fixed", pricing_value: default_rate }
    end

    private

    def manual_matrix
      adult_counts.index_with { |adults| price_for(adults).to_s.to_d.round(2) }
    end

    def derived_matrix
      adjustment = RoomTypeRatePlan.new(pricing_mode: derive_mode, pricing_value: derive_value)
      adult_counts.index_with do |adults|
        adjustment.derive_price(standard_occupancy_prices.fetch(adults)).round(2)
      end
    end

    def standard_occupancy_prices
      @standard_occupancy_prices ||= begin
        plan = room_type&.standard_rate_plan
        assignment = room_type&.room_type_rate_plans&.includes(:occupancy_prices)&.find_by(rate_plan: plan)
        assignment&.occupancy_prices&.index_by(&:adults)&.transform_values(&:price) || {}
      end
    end

    def rate_mode_is_offered
      return if available_modes.include?(rate_mode)

      errors.add(:rate_mode, "is not available for this property")
    end

    def manual_prices_are_complete
      missing = adult_counts.reject { |adults| price_for(adults).to_s.present? }
      return if missing.empty?

      errors.add(:base, "Enter a price for #{missing.map { |n| pluralize_adults(n) }.to_sentence}")
    end

    def manual_rate_is_present
      errors.add(:default_rate, "can't be blank") if default_rate.blank?
    end

    def derive_value_is_present
      errors.add(:derive_value, "can't be blank") if derive_value.blank?
    end

    # A derived per-person plan is anchored on the category's standard rate, so
    # a category saved without one has nothing to step away from. Say that
    # here rather than letting the ladder build a matrix of zeroes.
    def anchor_is_available
      return if adult_counts.all? { |adults| standard_occupancy_prices[adults].present? }

      errors.add(:base, "#{room_type&.name} needs a complete Standard Rate occupancy matrix before this price can be derived.")
    end

    def auto_rate_is_present
      errors.add(:default_rate, "can't be blank") if default_rate.blank?
    end

    def pluralize_adults(count) = "#{count} #{count == 1 ? 'adult' : 'adults'}"
  end
end
