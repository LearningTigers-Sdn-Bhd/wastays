# frozen_string_literal: true

module Rates
  # Audits the local setup horizon independently from channel synchronization.
  # A closed inventory row is configured but not sellable; an absent row is a
  # configuration gap.
  class SetupCoverage
    EMPTY_RATES = [].freeze

    RoomResult = Data.define(:room_type_id, :room_name, :configured_days, :sellable_days, :missing_dates, :unsellable_dates)
    Result = Data.define(
      :start_date, :end_date, :total_days, :total_slots, :configured_days,
      :sellable_days, :configured_percentage, :sellable_percentage,
      :room_results, :gaps, :expires_on, :expiring
    ) do
      # What "priced and stocked, no holes" means, asked once so onboarding and
      # the go-live gate cannot drift apart on the answer. A property with no
      # rooms configures zero of zero slots, which is vacuously whole — hence
      # the positive guards rather than a bare equality.
      def fully_configured? = total_slots.positive? && configured_days == total_slots
      def every_room_sellable? = room_results.any? && room_results.none? { |room| room.sellable_days.zero? }
      def unsellable_gaps? = gaps.any? { |gap| gap[:type] == "unsellable" }
      def complete? = fully_configured? && every_room_sellable? && !unsellable_gaps?
    end

    def self.call(...) = new(...).call

    def initialize(hotel:, start_date: Date.current, end_date: Date.current + 364.days)
      @hotel = hotel
      @start_date = start_date.to_date
      @end_date = end_date.to_date
    end

    def call
      dates = (start_date..end_date).to_a
      rooms = hotel.room_types.includes(
        :room_inventories,
        :room_rates,
        room_type_rate_plans: [ :occupancy_prices, :rate_plan ]
      ).order(:id).to_a
      inventories_by_room = rooms.to_h do |room|
        [ room.id, room.room_inventories.index_by(&:date) ]
      end
      rates_by_room_and_date = rooms.to_h do |room|
        [ room.id, room.room_rates.group_by(&:date) ]
      end

      results = rooms.map do |room|
        coverage_for(room, dates, inventories_by_room.fetch(room.id), rates_by_room_and_date.fetch(room.id))
      end
      total_slots = dates.size * rooms.size
      configured = results.sum(&:configured_days)
      sellable = results.sum(&:sellable_days)
      fully_configured_dates = dates.take_while do |date|
        rooms.any? && rooms.all? { |room| inventories_by_room.fetch(room.id).key?(date) }
      end

      Result.new(
        start_date: start_date,
        end_date: end_date,
        total_days: dates.size,
        total_slots: total_slots,
        configured_days: configured,
        sellable_days: sellable,
        configured_percentage: percentage(configured, total_slots),
        sellable_percentage: percentage(sellable, total_slots),
        room_results: results,
        gaps: results.flat_map { |result| gap_rows(result) } + plan_gap_rows(rooms, dates, rates_by_room_and_date),
        expires_on: fully_configured_dates.last,
        expiring: fully_configured_dates.last.nil? || fully_configured_dates.last <= Date.current + 30.days
      )
    end

    private

    attr_reader :hotel, :start_date, :end_date

    def coverage_for(room, dates, inventories, rates_by_date)
      missing = []
      unsellable = []
      configured = 0
      sellable = 0

      dates.each do |date|
        inventory = inventories[date]
        unless inventory
          missing << date
          next
        end

        configured += 1
        if inventory.status == "open" && inventory.quantity.positive? && standard_sellable?(room, date, rates_by_date)
          sellable += 1
        elsif inventory.status == "open"
          unsellable << date
        end
      end

      RoomResult.new(
        room_type_id: room.id,
        room_name: room.name,
        configured_days: configured,
        sellable_days: sellable,
        missing_dates: missing,
        unsellable_dates: unsellable
      )
    end

    def standard_sellable?(room, date, rates_by_date)
      plan = room.standard_rate_plan
      return false unless plan

      adults = plan.sell_mode == "per_person" ? (1..room.max_adults) : [ plan.base_occupancy.clamp(1, room.max_adults) ]
      adults.all? do |adult_count|
        Rates::ResolveEffectiveNightlyPrice.call(
          room_type: room,
          rate_plan: plan,
          date: date,
          currency: plan.currency,
          adults: adult_count,
          children: 0,
          room_rates: rates_by_date.fetch(date, EMPTY_RATES),
          room_type_rate_plan: room.room_type_rate_plans.find { |assignment| assignment.rate_plan_id == plan.id }
        ).amount&.positive?
      end
    end

    def gap_rows(result)
      rows = []
      rows << { room_type_id: result.room_type_id, room_name: result.room_name, type: "missing_inventory", dates: result.missing_dates } if result.missing_dates.any?
      rows << { room_type_id: result.room_type_id, room_name: result.room_name, type: "unsellable", dates: result.unsellable_dates } if result.unsellable_dates.any?
      rows
    end

    def plan_gap_rows(rooms, dates, rates_by_room_and_date)
      room_by_id = rooms.index_by(&:id)
      hotel.rate_plans.active.where(kind: "custom").includes(
        room_type_rate_plans: [ :occupancy_prices, :room_type ]
      ).flat_map do |plan|
        assignments = plan.room_type_rate_plans
        if assignments.empty?
          [ { rate_plan_id: plan.id, rate_plan_name: plan.name, type: "missing_assignment", dates: [] } ]
        else
          assignments.filter_map do |assignment|
            room = room_by_id[assignment.room_type_id] || assignment.room_type
            rates_by_date = rates_by_room_and_date.fetch(room.id)
            missing = dates.reject { |date| assignment_sellable?(assignment, room, plan, date, rates_by_date) }
            next if missing.empty?

            {
              room_type_id: room.id,
              room_name: room.name,
              rate_plan_id: plan.id,
              rate_plan_name: plan.name,
              type: "missing_plan_price",
              dates: missing
            }
          end
        end
      end
    end

    def assignment_sellable?(assignment, room, plan, date, rates_by_date)
      adults = plan.sell_mode == "per_person" ? (1..room.max_adults) : [ plan.base_occupancy.clamp(1, room.max_adults) ]
      adults.all? do |count|
        Rates::ResolveEffectiveNightlyPrice.call(
          room_type: room,
          rate_plan: plan,
          date: date,
          currency: plan.currency,
          adults: count,
          children: 0,
          room_rates: rates_by_date.fetch(date, EMPTY_RATES),
          room_type_rate_plan: assignment
        ).amount&.positive?
      end
    end

    def percentage(value, total)
      return 0.to_d if total.zero?

      (value.to_d * 100 / total).round(2)
    end
  end
end
