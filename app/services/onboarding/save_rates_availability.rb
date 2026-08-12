# frozen_string_literal: true

module Onboarding
  # Saves pricing, assignments, the initial calendar and onboarding progress as
  # one unit. All persisted rows remain ordinary rate/inventory domain records;
  # onboarding owns no shadow copy of this setup.
  class SaveRatesAvailability
    Result = ApplicationResult.define(:section, :entries, :coverage)
    MAX_CHILD_BANDS = 4
    PLAN_FIELDS = %w[
      id client_key _destroy name rate_mode derive_mode derive_value
    ].freeze
    ASSIGNMENT_FIELDS = %w[
      id client_key _destroy room_type_id default_rate
      base_occupancy extra_pax_charge single_supplement
      primary_occupancy increase_by increase_unit decrease_by decrease_unit
    ].freeze
    PRICING_FIELDS = %w[
      rate_mode default_rate derive_mode derive_value primary_occupancy
      increase_by increase_unit decrease_by decrease_unit
    ].freeze
    DOWNSTREAM_SECTIONS = %w[
      extra_charges discounts payment_methods corporate_accounts channel_manager review
    ].freeze

    def self.call(...) = new(...).call

    def initialize(hotel:, actor:, params:, complete:)
      @hotel = hotel
      @actor = actor
      @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      @complete = complete
    end

    def call
      previous_skip = Thread.current[:skip_ari_sync]
      return failure("Add at least one room category before setting rates.") if rooms.empty?
      return failure("One or more submitted records do not belong to this property.") if foreign_ids?
      return failure(child_band_error) if child_band_error.present?

      transition = nil
      coverage = nil
      before_signature = material_signature
      Thread.current[:skip_ari_sync] = true

      Hotel.transaction do
        save_standard_rows!
        save_custom_plans!
        @hotel.rate_plans.reset
        @hotel.room_types.reset

        population = HotelOps::PopulateRatesAvailability.call(
          hotel: @hotel,
          actor: @actor,
          start_date: start_date,
          end_date: end_date,
          weekend_days: weekend_days,
          room_rules: availability_entries,
          weekend_rules: persisted_weekend_rules
        )
        fail_transaction!(population.error) unless population.success?

        coverage = Rates::SetupCoverage.call(hotel: @hotel, start_date: start_date, end_date: end_date)
        fail_transaction!(completion_error(coverage)) if complete && completion_error(coverage).present?

        material_change = before_signature != material_signature
        if material_change
          invalidation = InvalidateDependentSections.call(
            hotel: @hotel,
            section_keys: DOWNSTREAM_SECTIONS,
            actor: @actor,
            source: "rates_availability_change",
            explanation: "Rates or availability changed. Review downstream commercial and channel setup before launch."
          )
          fail_transaction!(invalidation.error) unless invalidation.success?
        end

        transition = transition_section(material_change, coverage)
        fail_transaction!(transition.error) unless transition.success?
      end

      return failure(@error) if @error.present?

      Result.success(section: transition.section, entries: persisted_entries, coverage: coverage)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => error
      failure(error.record.errors.full_messages.to_sentence.presence || error.message)
    rescue ActiveRecord::RecordNotFound
      failure("One or more submitted records do not belong to this property.")
    ensure
      Thread.current[:skip_ari_sync] = previous_skip
    end

    private

    attr_reader :hotel, :actor, :params, :complete

    def save_standard_rows!
      standard_entries.each_with_index do |entry, index|
        room = rooms_by_id.fetch(entry["room_type_id"].to_s)
        plan = room.standard_rate_plan
        fail_transaction!("Room #{room.name} has no dedicated Standard Rate.") unless plan&.standard_rate?
        apply_child_bands!(plan)

        pricing = pricing_form(entry, room)
        if hotel.sells_per_person?
          result = RatePlans::SaveRoomPricing.call(rate_plan: plan, room_type: room, pricing: pricing)
          fail_transaction!("Standard Rate row #{index + 1}: #{result.error}") unless result.success?
        else
          fail_transaction!("Standard Rate row #{index + 1}: #{pricing.errors.full_messages.to_sentence}") unless pricing.valid?
          room.update!(base_price: pricing.default_rate)
        end
        apply_occupancy_rules!(plan, room, entry)
        apply_age_band_prices!(plan, room, entry)
        remember_weekend_rule(room, plan)
      end
    end

    def save_custom_plans!
      custom_plan_entries.each_with_index do |entry, index|
        if destroy?(entry)
          destroy_custom_plan!(entry)
          next
        end
        next if blank_new_plan?(entry)

        plan = entry["id"].present? ? custom_plans.find(entry["id"]) : hotel.rate_plans.build(
          kind: "custom", currency: hotel.default_currency.presence || "MYR"
        )
        plan.assign_attributes(name: entry["name"].to_s.strip)
        fail_transaction!("Rate plan #{index + 1}: #{plan.errors.full_messages.to_sentence}") unless plan.save
        apply_child_bands!(plan)

        assignment_entries = normalized_assignments(entry)
        retained = assignment_entries.reject { |assignment| destroy?(assignment) || blank_assignment?(assignment) }
        fail_transaction!("#{plan.name}: add at least one room category.") if retained.empty?
        duplicate_rooms = retained.map { |assignment| assignment["room_type_id"].to_s }
        fail_transaction!("#{plan.name}: each room category can be assigned only once.") if duplicate_rooms.uniq.size != duplicate_rooms.size

        # Attach replacement rows first so an atomic reassignment never crosses
        # the final-assignment guard while the transaction is in progress.
        retained.each_with_index do |assignment_entry, assignment_index|
          room = rooms_by_id.fetch(assignment_entry["room_type_id"].to_s)
          pricing = pricing_form(assignment_entry, room, entry)
          result = RatePlans::SaveRoomPricing.call(rate_plan: plan, room_type: room, pricing: pricing)
          fail_transaction!("#{plan.name}, row #{assignment_index + 1}: #{result.error}") unless result.success?
          apply_occupancy_rules!(plan, room, assignment_entry)
          apply_age_band_prices!(plan, room, assignment_entry)
          remember_weekend_rule(room, plan)
        end

        retained_ids = retained.map { |assignment| assignment["room_type_id"].to_i }
        plan.room_type_rate_plans.where.not(room_type_id: retained_ids).includes(:room_type).each do |assignment|
          removal = RatePlans::RemoveRoomType.call(rate_plan: plan, room_type: assignment.room_type)
          fail_transaction!("#{plan.name}: #{removal.error}") unless removal.success?
        end
      end
    end

    def destroy_custom_plan!(entry)
      return if entry["id"].blank?

      plan = custom_plans.find(entry["id"])
      fail_transaction!("#{plan.name} cannot be removed because an existing booking uses it.") unless plan.deletable?
      plan.destroy!
    end

    # What a room includes belongs to the pairing, not to the plan: one plan
    # covers a single and a suite, and they do not include the same number of
    # pax. Blank stays blank so the plan's own figure still answers.
    # Band prices are per room per plan, keyed by the band's position rather than
    # its id: the bands are rewritten on every save, so ids are not stable across
    # one submission but the order the operator sees them in is.
    def apply_age_band_prices!(plan, room, entry)
      return unless hotel.sells_per_person?

      assignment = plan.room_type_rate_plans.find_by(room_type: room)
      return if assignment.nil?

      submitted = indexed_values(entry["age_band_prices"])
      bands = plan.rate_plan_age_bands.reload.to_a

      assignment.age_band_prices.destroy_all
      bands.each_with_index do |band, index|
        price = optional_decimal(submitted[index.to_s])
        next if price.nil?

        assignment.age_band_prices.create!(rate_plan_age_band: band, price: price)
      end
    end

    # Scalar fields submitted under an index — `[age_band_prices][0]` — arrive as
    # a hash of strings from the form and as an array when they round-trip
    # through the session.
    def indexed_values(value)
      collection = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
      return collection.transform_keys(&:to_s) if collection.is_a?(Hash)

      Array(collection).each_with_index.to_h { |item, index| [ index.to_s, item ] }
    end

    def apply_occupancy_rules!(plan, room, entry)
      assignment = plan.room_type_rate_plans.find_by(room_type: room)
      return if assignment.nil?

      assignment.update!(
        base_occupancy: integer(entry["base_occupancy"]),
        extra_pax_charge: optional_decimal(entry["extra_pax_charge"]),
        single_supplement: optional_decimal(entry["single_supplement"])
      )
    end

    # How a plan gets its prices is one decision, made once in the plan heading.
    # It is still stored per assignment, so it is merged into every row here
    # rather than asked for on each of them.
    def plan_pricing(entry)
      basis = entry["rate_mode"].to_s
      return { "rate_mode" => "manual" } unless basis.start_with?("derived")

      {
        "rate_mode" => "derived",
        "derive_mode" => (basis == "derived_offset" ? "offset" : "multiplier"),
        "derive_value" => entry["derive_value"]
      }
    end

    def pricing_form(entry, room, plan_entry = nil)
      attributes = entry.slice(*PRICING_FIELDS, "prices")
      attributes = attributes.merge(plan_pricing(plan_entry)) if plan_entry

      HotelPortal::RatePlanRoomPricing.from_h(
        attributes,
        room_type: room,
        sells_per_person: hotel.sells_per_person?
      )
    end

    # One child policy for the property, written to every plan. The price lives
    # on the band rather than per room, which is what keeps this a fan-out
    # instead of a new table.
    def child_band_attributes
      return @child_band_attributes if defined?(@child_band_attributes)

      @child_band_attributes = if hotel.sells_per_person?
        normalize_collection(params["child_bands"]).reject { |band| band["min_age"].blank? && band["max_age"].blank? }
                                                   .each_with_index.map do |band, index|
          {
            min_age: integer(band["min_age"]),
            max_age: integer(band["max_age"]),
            label: band["label"].to_s.strip.presence,
            pricing_mode: (band["pricing_mode"] if band["pricing_mode"].in?(RatePlanAgeBand::PRICING_MODES)),
            position: index
          }.compact
        end
      else
        []
      end
    end

    # A gap leaves children of that age unpriced, which the ladder cannot detect
    # and the booking engine would resolve to the full adult rate.
    def child_band_error
      return nil unless hotel.sells_per_person?

      bands = child_band_attributes
      return "Add at least one child age band." if bands.empty?
      return "Use at most #{MAX_CHILD_BANDS} child age bands." if bands.size > MAX_CHILD_BANDS
      return "Each child age band needs a start and end age." if bands.any? { |band| band[:min_age].nil? || band[:max_age].nil? }
      return "Each child age band must end on or after it starts." if bands.any? { |band| band[:max_age] < band[:min_age] }

      sorted = bands.sort_by { |band| band[:min_age] }
      return "Child age bands cannot overlap or leave a gap." if sorted.each_cons(2).any? { |before, after| after[:min_age] != before[:max_age] + 1 }
      return "Child age bands must cover ages #{RatePlanAgeBand::REQUIRED_AGE_RANGE.min}–#{RatePlanAgeBand::REQUIRED_AGE_RANGE.max}." unless
        sorted.first[:min_age] == RatePlanAgeBand::REQUIRED_AGE_RANGE.min &&
          sorted.last[:max_age] >= RatePlanAgeBand::REQUIRED_AGE_RANGE.max

      nil
    end

    # Rebuild by position because every plan receives the same age policy. Keep
    # each plan's legacy percentage/amount fallback at that position so the
    # first save after room-specific pricing ships cannot erase old prices.
    def apply_child_bands!(plan)
      return if child_band_attributes.empty?

      legacy_prices = plan.rate_plan_age_bands.to_a.map do |band|
        { pricing_mode: band.pricing_mode, price_value: band.price_value }
      end
      plan.rate_plan_age_bands.destroy_all
      child_band_attributes.each_with_index do |attributes, index|
        fallback = legacy_prices[index] || { pricing_mode: "amount", price_value: 0 }
        plan.rate_plan_age_bands.create!(fallback.merge(attributes))
      end
    end

    def persisted_weekend_rules
      @persisted_weekend_rules || []
    end

    # One uplift for the property rather than a mode and value on every row. The
    # calendar still wants a rule per room/plan pair, so the single figure is
    # fanned out to each of them here.
    def remember_weekend_rule(room, plan)
      (@persisted_weekend_rules ||= []) << {
        "room_type_id" => room.id,
        "rate_plan_id" => plan.id,
        "adjustment_mode" => weekend_uplift_mode,
        "adjustment_value" => weekend_uplift_value
      }
    end

    def weekend_uplift = @weekend_uplift ||= (params["weekend_uplift"] || {}).to_h.deep_stringify_keys
    def weekend_uplift_mode = weekend_uplift["adjustment_mode"].to_s.in?(%w[amount percent]) ? weekend_uplift["adjustment_mode"] : "percent"
    def weekend_uplift_value = weekend_uplift["adjustment_value"].presence || "0"

    def completion_error(coverage)
      custom_names = custom_plans.where(archived_at: nil).pluck(:name).map { |name| name.to_s.strip.downcase }
      return "Custom rate plan names must be unique." if custom_names.uniq.size != custom_names.size
      return "Every custom room assignment needs positive pricing." unless custom_assignments_positive?
      return "Configure every room for the complete 365-day horizon." unless coverage.fully_configured?
      return "Every room category needs at least one sellable date." unless coverage.every_room_sellable?
      return "Resolve open dates without positive Standard pricing or inventory." if coverage.unsellable_gaps?

      nil
    end

    def custom_assignments_positive?
      custom_plans.includes(room_type_rate_plans: [ :occupancy_prices, :room_type ]).all? do |plan|
        plan.room_type_rate_plans.any? && plan.room_type_rate_plans.all? do |assignment|
          adult_counts = hotel.sells_per_person? ? (1..assignment.room_type.max_adults) : [ plan.base_occupancy.clamp(1, assignment.room_type.max_adults) ]
          adult_counts.all? do |adults|
            Rates::ResolveEffectiveNightlyPrice.call(
              room_type: assignment.room_type,
              rate_plan: plan,
              date: start_date,
              currency: plan.currency,
              adults: adults,
              children: 0,
              room_rates: [],
              room_type_rate_plan: assignment
            ).amount&.positive?
          end
        end
      end
    end

    def transition_section(material_change, coverage)
      if !complete && !material_change && section.state == "complete"
        return Result.success(section: section, entries: persisted_entries, coverage: coverage)
      end

      state = if complete
        "complete"
      elsif material_change && section.state == "complete"
        "needs_attention"
      elsif section.state == "needs_attention"
        "needs_attention"
      else
        "in_progress"
      end
      UpdateSection.new(
        hotel: hotel,
        section_key: "rates_availability",
        state: state,
        actor: actor,
        metadata: {
          source: "rates_availability_setup",
          horizon_start: start_date,
          horizon_end: end_date,
          configured_percentage: coverage.configured_percentage,
          sellable_percentage: coverage.sellable_percentage
        }
      ).call
    end

    def material_signature
      room_ids = hotel.room_types.pluck(:id)
      plan_ids = hotel.rate_plans.where(kind: %w[standard custom]).pluck(:id)
      [
        hotel.room_types.order(:id).pluck(:id, :base_price),
        hotel.rate_plans.where(id: plan_ids).order(:id).pluck(
          :id, :name, :base_occupancy, :extra_pax_charge,
          :single_supplement, :child_price_multiplier, :archived_at
        ),
        RoomTypeRatePlan.where(room_type_id: room_ids, rate_plan_id: plan_ids).order(:id).pluck(
          :id, :room_type_id, :rate_plan_id, :pricing_mode, :pricing_value
        ),
        RoomTypeRatePlanOccupancyPrice.joins(:room_type_rate_plan)
          .where(room_type_rate_plans: { room_type_id: room_ids, rate_plan_id: plan_ids })
          .order(:room_type_rate_plan_id, :adults).pluck(:room_type_rate_plan_id, :adults, :price),
        RatePlanAgeBand.where(rate_plan_id: plan_ids).order(:rate_plan_id, :position, :min_age)
          .pluck(:rate_plan_id, :min_age, :max_age, :pricing_mode, :price_value, :label, :position),
        RoomTypeRatePlanAgeBandPrice.joins(:room_type_rate_plan, :rate_plan_age_band)
          .where(room_type_rate_plans: { room_type_id: room_ids, rate_plan_id: plan_ids })
          .order(:room_type_rate_plan_id, "rate_plan_age_bands.position")
          .pluck(:room_type_rate_plan_id, "rate_plan_age_bands.position", :price),
        RoomInventory.where(room_type_id: room_ids, date: start_date..end_date).order(:room_type_id, :date)
          .pluck(:room_type_id, :date, :quantity, :status),
        RoomRate.where(room_type_id: room_ids, rate_plan_id: plan_ids, date: start_date..end_date)
          .order(:room_type_id, :rate_plan_id, :date).pluck(
            :room_type_id, :rate_plan_id, :date, :price, :occupancy_prices,
            :base_occupancy, :extra_pax_charge, :single_supplement,
            :applied_rule_type
          )
      ]
    end

    def fail_transaction!(message)
      @error = message.presence || "Rates and availability could not be saved."
      raise ActiveRecord::Rollback
    end

    def foreign_ids?
      standard_ids = standard_entries.map { |entry| entry["room_type_id"].to_s }
      assignment_ids = custom_plan_entries.flat_map { |plan| normalized_assignments(plan) }.map { |entry| entry["room_type_id"].to_s }.reject(&:blank?)
      plan_ids = custom_plan_entries.filter_map { |entry| entry["id"].presence }
      (standard_ids + assignment_ids).uniq.any? { |id| !rooms_by_id.key?(id) } ||
        plan_ids.any? { |id| !custom_plans.where(id: id).exists? }
    end

    def standard_entries = normalize_collection(params["standard_entries"])
    def custom_plan_entries = normalize_collection(params["custom_plans"]).map { |entry| entry.slice(*PLAN_FIELDS, "assignments") }
    def availability_entries = normalize_collection(params["availability_entries"])
    def normalized_assignments(entry) = normalize_collection(entry["assignments"]).map { |item| item.slice(*ASSIGNMENT_FIELDS, "prices", "age_band_prices") }

    def normalize_collection(value)
      collection = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h.values : (value.is_a?(Hash) ? value.values : Array(value))
      collection.map { |item| (item.respond_to?(:to_unsafe_h) ? item.to_unsafe_h : item.to_h).deep_stringify_keys }
    end

    def rooms = @rooms ||= hotel.room_types.includes(room_type_rate_plans: [ :occupancy_prices, :rate_plan ]).order(:id).to_a
    def rooms_by_id = @rooms_by_id ||= rooms.index_by { |room| room.id.to_s }
    def custom_plans = hotel.rate_plans.active.where(kind: "custom")
    def start_date = @start_date ||= parse_date(params["start_date"]) || Date.current
    def end_date = @end_date ||= parse_date(params["end_date"]) || start_date + 364.days
    def weekend_days = Array(params["weekend_days"]).presence || %w[0 6]
    def destroy?(entry) = ActiveModel::Type::Boolean.new.cast(entry["_destroy"])
    # Rows come pre-filled with every room category, so a plan cannot be judged
    # blank by its assignments any more. An unnamed new plan is the clone source
    # submitting itself when JavaScript is off.
    def blank_new_plan?(entry) = entry["id"].blank? && entry["name"].blank?
    def blank_assignment?(entry) = entry["room_type_id"].blank?
    def integer(value) = Integer(value, exception: false)
    def decimal(value) = value.to_s.presence&.to_d || 0.to_d
    # Blank means "no rule of its own", which is not the same as zero.
    def optional_decimal(value) = value.to_s.presence&.to_d
    def parse_date(value) = value.present? ? value.to_date : nil

    def section
      @section ||= begin
        InitializeProgress.new(hotel: hotel, actor: actor).call
        hotel.onboarding_sections.find_by!(section_key: "rates_availability")
      end
    end

    def persisted_entries
      { "start_date" => start_date.to_s, "end_date" => end_date.to_s }
    end

    def failure(message)
      Result.failure(message.presence || "Rates and availability could not be saved.", section: section, entries: params, coverage: nil)
    end
  end
end
