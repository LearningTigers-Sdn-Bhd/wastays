# frozen_string_literal: true

module HotelOps
  # Materializes the initial inventory horizon and the dated prices that differ
  # from standing assignment pricing. It is shared domain behavior: onboarding
  # supplies the rules, while this class owns calendar persistence, audit, and a
  # single post-commit ARI request.
  class PopulateRatesAvailability
    Result = ApplicationResult.define(:start_date, :end_date, :room_type_ids, :rate_plan_ids)
    GENERATED_RULE_TYPES = %w[onboarding_weekend onboarding_exception].freeze
    ADJUSTMENT_MODES = %w[amount percent].freeze

    def self.call(...) = new(...).call

    def initialize(hotel:, actor:, start_date:, end_date:, weekend_days:, room_rules:,
                   weekend_rules:, exceptions: [])
      @hotel = hotel
      @actor = actor
      @start_date = parse_date(start_date)
      @end_date = parse_date(end_date)
      @weekend_days = Array(weekend_days).filter_map { |day| Integer(day, exception: false) }.uniq
      @room_rules = normalize_collection(room_rules)
      @weekend_rules = normalize_collection(weekend_rules)
      @exceptions = normalize_collection(exceptions)
    end

    def call
      previous_skip = Thread.current[:skip_ari_sync]
      return failure("Start date is required.") unless start_date
      return failure("End date is required.") unless end_date
      return failure("End date cannot be earlier than start date.") if end_date < start_date
      return failure("Availability can be populated for at most two years at a time.") if (end_date - start_date).to_i > 730
      return failure("Choose at least one weekend day.") if weekend_days.empty?
      return failure("Each room category must have one availability rule.") if duplicate_room_rules? || rooms.size != room_rules.size
      return failure("Available quantity must be between zero and the room quantity.") unless valid_room_quantities?
      return failure("Each room/rate assignment must have one pricing rule.") if duplicate_weekend_rules?
      return failure("One or more rate-plan assignments do not belong to this property.") unless assignments_by_key.size == weekend_rules.size

      Thread.current[:skip_ari_sync] = true

      ActiveRecord::Base.transaction do
        remove_generated_rates!
        populate_inventory!
        populate_weekends!
        apply_exceptions!
        write_audit!
      end

      enqueue_sync
      Result.success(
        start_date: start_date,
        end_date: end_date,
        room_type_ids: rooms.map(&:id),
        rate_plan_ids: assignments_by_key.values.map(&:rate_plan_id).uniq
      )
    rescue ActiveRecord::RecordInvalid, ArgumentError => error
      failure(error.message)
    ensure
      Thread.current[:skip_ari_sync] = previous_skip
    end

    private

    attr_reader :hotel, :actor, :start_date, :end_date, :weekend_days, :room_rules,
                :weekend_rules, :exceptions

    def parse_date(value)
      value.present? ? value.to_date : nil
    rescue ArgumentError
      nil
    end

    def normalize_collection(value)
      collection = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h.values : (value.is_a?(Hash) ? value.values : Array(value))
      collection.map { |item| (item.respond_to?(:to_unsafe_h) ? item.to_unsafe_h : item.to_h).deep_stringify_keys }
    end

    def rooms
      @rooms ||= hotel.room_types.where(id: room_rules.map { |rule| rule["room_type_id"] }).order(:id).to_a
    end

    def room_by_id
      @room_by_id ||= rooms.index_by { |room| room.id.to_s }
    end

    def assignments_by_key
      @assignments_by_key ||= begin
        pairs = weekend_rules.map { |rule| [ rule["room_type_id"].to_i, rule["rate_plan_id"].to_i ] }
        RoomTypeRatePlan.includes(:occupancy_prices, :rate_plan, room_type: :hotel)
          .where(room_type_id: pairs.map(&:first), rate_plan_id: pairs.map(&:last))
          .select { |assignment| assignment.room_type.hotel_id == hotel.id }
          .index_by { |assignment| [ assignment.room_type_id.to_s, assignment.rate_plan_id.to_s ] }
      end
    end

    def valid_room_quantities?
      room_rules.all? do |rule|
        room = room_by_id[rule["room_type_id"].to_s]
        quantity = integer(rule["quantity"])
        room && quantity && quantity.between?(0, room.quantity)
      end
    end

    def duplicate_room_rules?
      ids = room_rules.map { |rule| rule["room_type_id"].to_s }
      ids.uniq.size != ids.size
    end

    def duplicate_weekend_rules?
      keys = weekend_rules.map { |rule| [ rule["room_type_id"].to_s, rule["rate_plan_id"].to_s ] }
      keys.uniq.size != keys.size
    end

    def remove_generated_rates!
      RoomRate.where(
        room_type_id: rooms.map(&:id),
        rate_plan_id: assignments_by_key.values.map(&:rate_plan_id),
        date: start_date..end_date,
        applied_rule_type: GENERATED_RULE_TYPES
      ).delete_all
    end

    def populate_inventory!
      room_rules.each do |rule|
        room = room_by_id.fetch(rule["room_type_id"].to_s)
        quantity = integer(rule["quantity"])
        status = rule["status"].to_s.in?(%w[open closed]) ? rule["status"].to_s : "open"

        (start_date..end_date).each do |date|
          inventory = room.room_inventories.find_or_initialize_by(date: date)
          inventory.assign_attributes(quantity: quantity, status: status)
          inventory.available_room_numbers = [] if inventory.new_record?
          inventory.save!
        end
      end
    end

    def populate_weekends!
      weekend_rules.each do |rule|
        assignment = assignments_by_key.fetch([ rule["room_type_id"].to_s, rule["rate_plan_id"].to_s ])
        next if decimal(rule["adjustment_value"]).zero?

        (start_date..end_date).select { |date| weekend_days.include?(date.wday) }.each do |date|
          write_adjusted_rate!(assignment, date, rule, "onboarding_weekend")
        end
      end
    end

    def apply_exceptions!
      exceptions.each do |rule|
        exception_start = parse_date(rule["start_date"])
        exception_end = parse_date(rule["end_date"]) || exception_start
        raise ArgumentError, "Exception dates must fall within the availability range." unless exception_start && exception_end &&
          exception_start >= start_date && exception_end <= end_date && exception_end >= exception_start

        exception_rooms(rule).each do |room|
          (exception_start..exception_end).each do |date|
            apply_inventory_exception!(room, date, rule)
            exception_assignments(room, rule).each do |assignment|
              write_adjusted_rate!(assignment, date, rule, "onboarding_exception") if rule["adjustment_value"].present?
            end
          end
        end
      end
    end

    def apply_inventory_exception!(room, date, rule)
      return if rule["status"].blank? && rule["quantity"].blank?

      inventory = room.room_inventories.find_or_initialize_by(date: date)
      inventory.status = rule["status"] if rule["status"].to_s.in?(%w[open closed])
      if rule["quantity"].present?
        quantity = integer(rule["quantity"])
        raise ArgumentError, "Exception quantity must be between zero and the room quantity." unless quantity&.between?(0, room.quantity)
        inventory.quantity = quantity
      end
      inventory.quantity ||= room.quantity
      inventory.available_room_numbers = []
      inventory.save!
    end

    def write_adjusted_rate!(assignment, date, rule, applied_rule_type)
      rate_plan = assignment.rate_plan
      currency = rate_plan.currency
      occupancy_prices = if rate_plan.sell_mode == "per_person"
        (1..assignment.room_type.max_adults).index_with do |adults|
          base = effective_amount(assignment, adults, date)
          raise ArgumentError, "#{rate_plan.name} is missing the #{adults}-adult price for #{assignment.room_type.name}." unless base
          adjusted(base, rule)
        end.transform_keys(&:to_s)
      else
        {}
      end
      base_price = if occupancy_prices.any?
        occupancy_prices.fetch(assignment.room_type.max_adults.to_s)
      else
        base = effective_amount(assignment, rate_plan.base_occupancy, date)
        raise ArgumentError, "#{rate_plan.name} has no standing price for #{assignment.room_type.name}." unless base
        adjusted(base, rule)
      end

      rate = RoomRate.find_or_initialize_by(
        room_type: assignment.room_type,
        rate_plan: rate_plan,
        date: date,
        currency: currency
      )
      rate.assign_attributes(
        price: base_price,
        occupancy_prices: occupancy_prices,
        applied_rule_type: applied_rule_type
      )
      rate.save!
    end

    def effective_amount(assignment, adults, date)
      result = Rates::ResolveEffectiveNightlyPrice.call(
        room_type: assignment.room_type,
        rate_plan: assignment.rate_plan,
        date: date,
        currency: assignment.rate_plan.currency,
        adults: adults,
        children: 0,
        room_type_rate_plan: assignment
      )
      result.base_amount
    end

    def adjusted(amount, rule)
      value = decimal(rule["adjustment_value"])
      result = if rule["adjustment_mode"] == "percent"
        amount.to_d * (1 + value / 100.to_d)
      else
        amount.to_d + value
      end
      [ result, 0.to_d ].max.round(2)
    end

    def exception_rooms(rule)
      ids = Array(rule["room_type_ids"].presence || rule["room_type_id"]).reject(&:blank?).map(&:to_s)
      selected = ids.empty? ? rooms : rooms.select { |room| ids.include?(room.id.to_s) }
      raise ArgumentError, "An exception references a room outside this property." if ids.any? && selected.size != ids.uniq.size
      selected
    end

    def exception_assignments(room, rule)
      ids = Array(rule["rate_plan_ids"].presence || rule["rate_plan_id"]).reject(&:blank?).map(&:to_s)
      assignments = room.room_type_rate_plans.includes(:occupancy_prices, :rate_plan).to_a
      selected = ids.empty? ? assignments : assignments.select { |assignment| ids.include?(assignment.rate_plan_id.to_s) }
      if ids.any? && selected.map { |assignment| assignment.rate_plan_id.to_s }.uniq.size != ids.uniq.size
        raise ArgumentError, "An exception references a rate plan not assigned to the selected room."
      end
      selected
    end

    def integer(value)
      Integer(value, exception: false)
    end

    def decimal(value)
      value.to_s.presence&.to_d || 0.to_d
    end

    def write_audit!
      rooms.each do |room|
        hotel.inventory_audit_logs.create!(
          room_type: room,
          user: actor,
          action_type: "bulk_inventory_update",
          old_value: {},
          new_value: { start_date: start_date, end_date: end_date },
          metadata: { source: "onboarding_rates_availability" }
        )
      end
    end

    def enqueue_sync
      return if hotel.preferred_channel_manager.blank?

      ActiveRecord.after_all_transactions_commit do
        ChannelManagers::SyncJob.perform_later(
          hotel.id,
          start_date,
          end_date,
          sync_availability: true,
          sync_rates: true,
          sync_restrictions: false,
          room_type_ids: rooms.map(&:id),
          rate_plan_ids: assignments_by_key.values.map(&:rate_plan_id).uniq
        )
      end
    end

    def failure(message)
      Result.failure(message, start_date: start_date, end_date: end_date, room_type_ids: [], rate_plan_ids: [])
    end
  end
end
