# frozen_string_literal: true

module HotelPortal
  # The draft behind the new-rate-plan wizard.
  #
  # It holds a plain hash — the shape that goes in and out of the session — and
  # hands out real objects on demand: an unsaved RatePlan for the details step so
  # the model's own validations and its age-band nested attributes work
  # unchanged, and a RoomPricing per selected category for the steps after it.
  # Nothing is written until the review step is confirmed.
  #
  # Steps are derived from the selection rather than stored, so changing which
  # categories are ticked immediately changes which steps exist, and a draft can
  # never point at a step that is no longer part of it.
  class RatePlanWizard
    STEP_DETAILS = "details"
    STEP_REVIEW = "review"

    # Plan-level pricing rules live on rate_plans, not per category, so they
    # belong to the details step. The room steps only carry money.
    #
    # single_supplement is absent on purpose: a per-person plan built here always
    # has a price for one adult, and Bookings::NightlyPaxPrice only falls back to
    # the supplement when no occupancy price exists. Asking for it would collect
    # a number that can never apply.
    DETAIL_ATTRIBUTES = %w[
      name description base_occupancy extra_pax_charge child_price_multiplier
    ].freeze

    attr_reader :hotel

    def initialize(hotel:, data: nil)
      @hotel = hotel
      @data = (data || {}).deep_stringify_keys
      @data["details"] ||= {}
      @data["rooms"] ||= {}
    end

    def to_h = @data

    def self.room_step(room_type_id) = "room-#{room_type_id}"

    def self.room_type_id_from(step)
      step.to_s[/\Aroom-(\d+)\z/, 1]&.to_i
    end

    # --- steps ---------------------------------------------------------------

    def step_keys
      [ STEP_DETAILS, *selected_room_types.map { |room_type| self.class.room_step(room_type.id) }, STEP_REVIEW ]
    end

    def step_exists?(step) = step_keys.include?(step.to_s)

    def step_index(step) = step_keys.index(step.to_s)

    def next_step(step)
      index = step_index(step)
      index && step_keys[index + 1]
    end

    def previous_step(step)
      index = step_index(step)
      index&.positive? ? step_keys[index - 1] : nil
    end

    def room_type_for_step(step)
      id = self.class.room_type_id_from(step)
      id && selected_room_types.find { |room_type| room_type.id == id }
    end

    def step_complete?(step)
      case step.to_s
      when STEP_DETAILS then details_captured?
      when STEP_REVIEW then false
      else
        room_type = room_type_for_step(step)
        room_type.present? && room_pricing(room_type).valid?
      end
    end

    # The furthest step the draft has actually earned. Deep-linking past a gap
    # lands here instead, so a half-filled draft can't reach the review step.
    def first_incomplete_step
      step_keys.find { |step| !step_complete?(step) } || STEP_REVIEW
    end

    def ready?
      details_captured? && selected_room_types.all? { |room_type| room_pricing(room_type).valid? }
    end

    # --- details step --------------------------------------------------------

    def details = @data["details"]

    def assign_details(attrs)
      @data["details"] = attrs.to_h.deep_stringify_keys
      @rate_plan = nil
      prune_dropped_rooms!
      self
    end

    def details_valid?
      rate_plan.validate
      rate_plan.errors.add(:room_types, "must include at least one room category") if selected_room_type_ids.empty?
      rate_plan.errors.empty?
    end

    def rate_plan
      @rate_plan ||= hotel.rate_plans.build(rate_plan_attributes)
    end

    def rate_plan_attributes
      attrs = details.slice(*DETAIL_ATTRIBUTES).compact_blank
      attrs["currency"] = hotel.default_currency.presence || "MYR"
      attrs["rate_plan_age_bands_attributes"] = age_band_attributes if hotel.sells_per_person?
      attrs
    end

    def selected_room_type_ids
      Array(details["room_type_ids"]).compact_blank.map(&:to_i)
    end

    def selected_room_types
      @selected_room_types ||= hotel.room_types.where(id: selected_room_type_ids).order(:id).to_a
    end

    # --- room steps ----------------------------------------------------------

    def room_pricing(room_type)
      RoomPricing.from_h(
        @data["rooms"][room_type.id.to_s],
        room_type: room_type,
        sells_per_person: hotel.sells_per_person?
      )
    end

    def assign_room(room_type, attrs)
      pricing = RoomPricing.from_h(attrs, room_type: room_type, sells_per_person: hotel.sells_per_person?)
      @data["rooms"][room_type.id.to_s] = pricing.to_h
      pricing
    end

    # Copies one step's answers onto every other selected category. Prices typed
    # per adult count carry across only as far as the target category can seat —
    # a 2-pax room takes the first two rungs and ignores the rest, and a deeper
    # room is left with the counts it still needs, rather than being quietly
    # filled with a shallower room's numbers.
    def apply_to_all_rooms(source_room_type)
      source = @data["rooms"][source_room_type.id.to_s]
      return self if source.blank?

      selected_room_types.each do |room_type|
        next if room_type.id == source_room_type.id

        @data["rooms"][room_type.id.to_s] = RoomPricing
          .from_h(source, room_type: room_type, sells_per_person: hotel.sells_per_person?)
          .to_h
      end
      self
    end

    def copy_room(source_room_type, target_room_type)
      source = @data["rooms"][source_room_type.id.to_s]
      return self if source.blank?

      @data["rooms"][target_room_type.id.to_s] = RoomPricing
        .from_h(source, room_type: target_room_type, sells_per_person: hotel.sells_per_person?)
        .to_h
      self
    end

    # Categories already answered, for the "copy from" picker on a room step.
    def answered_room_types(excluding:)
      selected_room_types.select do |room_type|
        room_type.id != excluding.id && @data["rooms"][room_type.id.to_s].present?
      end
    end

    private

    def details_captured?
      details["name"].to_s.present? && selected_room_type_ids.any?
    end

    # Nested attributes arrive index-keyed ({"0" => {...}}), which is what
    # accepts_nested_attributes_for wants — pass it through untouched.
    def age_band_attributes
      details["rate_plan_age_bands_attributes"].presence || {}
    end

    # Unticking a category mid-draft would otherwise leave its answers behind,
    # ready to be written on a later run if it were ticked again.
    def prune_dropped_rooms!
      keep = selected_room_type_ids.map(&:to_s)
      @data["rooms"].select! { |room_type_id, _| keep.include?(room_type_id) }
      @selected_room_types = nil
    end
  end
end
