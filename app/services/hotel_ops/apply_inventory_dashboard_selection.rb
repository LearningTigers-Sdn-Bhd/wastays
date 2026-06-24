# frozen_string_literal: true

module HotelOps
  class ApplyInventoryDashboardSelection
    def initialize(hotel:, selection:, user:, skip_sync: false)
      @hotel = hotel
      @selection = selection
      @user = user
      @skip_sync = skip_sync
    end

    def call
      return failure("Select at least one room type.") if room_types.empty?
      return failure("Choose at least one action to apply.") unless apply_inventory? || apply_rates? || apply_restrictions?
      return failure("Start date is required.") if start_date.blank?
      return failure("End date is required.") if end_date.blank?
      return failure("Price is required when applying rates.") if apply_rates? && price.blank? && selection[:single_supplement].blank? && selection[:base_occupancy].blank? && selection[:extra_pax_charge].blank?

      ActiveRecord::Base.transaction do
        Thread.current[:skip_ari_sync] = true

        room_types.each do |room_type|
          apply_inventory_to(room_type) if apply_inventory?
          apply_rates_to(room_type) if apply_rates? || apply_restrictions?
        end

        sync_to_channel_manager unless skip_sync
      end

      success
    rescue StandardError => e
      failure(e.message)
    ensure
      Thread.current[:skip_ari_sync] = nil unless skip_sync
    end

    private

    attr_reader :hotel, :selection, :user, :skip_sync

    def start_date
      @start_date ||= selection[:start_date].presence&.to_date
    end

    def end_date
      @end_date ||= selection[:end_date].presence&.to_date
    end

    def room_type_ids
      @room_type_ids ||= Array(selection[:room_type_ids]).reject(&:blank?).map(&:to_i)
    end

    def rate_plan_ids
      @rate_plan_ids ||= Array(selection[:rate_plan_ids]).reject(&:blank?).map { |id| id.to_s.match?(/^\d+$/) ? id.to_i : id.to_s }
    end

    def room_types
      @room_types ||= hotel.room_types.where(id: room_type_ids).includes(:rate_plans)
    end

    def selected_room_numbers
      @selected_room_numbers ||= Array(selection[:available_room_numbers]).reject(&:blank?).map(&:to_s)
    end

    def apply_inventory?
      cast_boolean(selection[:apply_inventory])
    end

    def apply_rates?
      cast_boolean(selection[:apply_rates])
    end

    def apply_restrictions?
      cast_boolean(selection[:apply_restrictions])
    end

    def quantity
      raw = selection[:quantity]
      return nil if raw.blank?

      raw.to_i
    end

    def status
      selection[:status].presence || "open"
    end

    def price
      raw = selection[:price]
      return nil if raw.blank?

      BigDecimal(raw.to_s)
    end

    def base_occupancy
      raw = selection[:base_occupancy]
      return nil if raw.blank?

      raw.to_i
    end

    def extra_pax_charge
      raw = selection[:extra_pax_charge]
      return nil if raw.blank?

      BigDecimal(raw.to_s)
    end

    def single_supplement
      raw = selection[:single_supplement]
      return nil if raw.blank?

      BigDecimal(raw.to_s)
    end

    def currency
      requested_currency = selection[:currency].presence || hotel.default_currency || "MYR"
      CurrencyCatalog.valid?(requested_currency) ? CurrencyCatalog.normalize(requested_currency) : hotel.default_currency
    end

    def restriction_values
      {
        min_stay: selection[:min_stay].presence,
        max_stay: selection[:max_stay].presence,
        closed_to_arrival: cast_boolean(selection[:closed_to_arrival]),
        closed_to_departure: cast_boolean(selection[:closed_to_departure]),
        stop_sell: cast_boolean(selection[:stop_sell])
      }
    end

    def rate_plans_for(room_type)
      scope = room_type.rate_plans
      scope = scope.where(id: rate_plan_ids) if rate_plan_ids.any?
      scope
    end

    def apply_inventory_to(room_type)
      room_numbers = room_numbers_for(room_type)

      (start_date..end_date).each do |date|
        inventory = room_type.room_inventories.find_or_initialize_by(date: date)
        old_quantity = inventory.quantity
        old_status = inventory.status
        old_room_numbers = inventory.available_room_numbers

        # Only update status if a value was explicitly provided
        inventory.status = status if selection[:status].present?

        if room_numbers
          occupied_count = occupied_room_count(date, room_numbers)
          inventory.available_room_numbers = room_numbers
          inventory.quantity = [ 0, room_numbers.size - occupied_count ].max
        elsif !quantity.nil?
          inventory.available_room_numbers = []
          inventory.quantity = quantity
        end
        inventory.quantity = room_type.quantity if inventory.quantity.nil?
        inventory.save!

        next unless old_quantity != inventory.quantity || old_status != inventory.status || old_room_numbers != inventory.available_room_numbers

        hotel.inventory_audit_logs.create!(
          room_type: room_type,
          user: user,
          action_type: "inventory_update",
          old_value: { date: date, quantity: old_quantity, status: old_status, room_numbers: old_room_numbers },
          new_value: { date: date, quantity: inventory.quantity, status: inventory.status, room_numbers: inventory.available_room_numbers },
          metadata: { source: "inventory_dashboard_selection" }
        )
      end
    end

    def apply_rates_to(room_type)
      # 1. Handle Standard Rate Plans
      real_rate_plan_ids = rate_plan_ids.select { |id| id.is_a?(Integer) }

      # If the user specifically selected rate plans (could be virtual tiers or standard ones),
      # we should only update standard plans if they are explicitly in the selection.
      # If NOTHING was selected (rate_plan_ids.empty?), then we default to updating all standard plans.
      if rate_plan_ids.empty? || real_rate_plan_ids.any?
        rate_plans_to_update = room_type.rate_plans
        rate_plans_to_update = rate_plans_to_update.where(id: real_rate_plan_ids) if real_rate_plan_ids.any?

        rate_plans_to_update.find_each do |rate_plan|
          update_rates_for_plan(room_type, rate_plan, tier: nil)
        end
      end

      # 2. Handle Virtual Pricing Tiers (Walk-in, Corporate, OTA)
      # These are stored on the room's master (first) rate plan
      master_plan = room_type.rate_plans.sort_by(&:id).first
      return if master_plan.blank?

      virtual_tier_keys = rate_plan_ids.select { |id| id.is_a?(String) && id.start_with?("tier_") }
      virtual_tier_keys.each do |key|
        # Virtual ID format: tier_[tier_type]_[room_type_id]
        parts = key.split("_")

        # Ensure we only process tiers for the current room_type
        next unless parts.last.to_i == room_type.id

        tier_type = if parts[1] == "walk" then :walk_in
        elsif parts[1] == "corporate" then :corporate
        elsif parts[1] == "ota" then :ota
        end

        update_rates_for_plan(room_type, master_plan, tier: tier_type) if tier_type
      end
    end

    def update_rates_for_plan(room_type, rate_plan, tier: nil)
      # Ensure rate plan currency follows the requested currency when applying rates
      if apply_rates? && rate_plan.currency != currency
        rate_plan.update!(currency: currency)
      end

      (start_date..end_date).each do |date|
        target_currencies_for(rate_plan, date).each do |target_currency|
          rate = rate_plan.room_rates.find_or_initialize_by(date: date, currency: target_currency)
          rate.room_type = room_type
          old_values = {
            price: rate.price&.to_f,
            walk_in_price: rate.walk_in_price&.to_f,
            corporate_price: rate.corporate_price&.to_f,
            ota_price: rate.ota_price&.to_f,
            min_stay: rate.min_stay,
            max_stay: rate.max_stay,
            closed_to_arrival: rate.closed_to_arrival,
            closed_to_departure: rate.closed_to_departure,
            stop_sell: rate.stop_sell,
            base_occupancy: rate.base_occupancy,
            extra_pax_charge: rate.extra_pax_charge&.to_f,
            single_supplement: rate.single_supplement&.to_f
          }

          # Apply price update.
          should_apply_price = apply_rates? && target_currency == currency
          if should_apply_price
            case tier
            when :walk_in then rate.walk_in_price = price
            when :corporate then rate.corporate_price = price
            when :ota then rate.ota_price = price
            else
              rate.price = price if selection[:price].present?
            end

            # Apply per-pax rules
            if selection[:modified_fields].present?
              rate.base_occupancy = base_occupancy if selection[:modified_fields].include?("base_occupancy")
              rate.extra_pax_charge = extra_pax_charge if selection[:modified_fields].include?("extra_pax_charge")
              rate.single_supplement = single_supplement if selection[:modified_fields].include?("single_supplement")
            else
              rate.base_occupancy = base_occupancy if selection.key?(:base_occupancy) && selection[:base_occupancy].present?
              rate.extra_pax_charge = extra_pax_charge if selection.key?(:extra_pax_charge) && selection[:extra_pax_charge].present?
              rate.single_supplement = single_supplement if selection.key?(:single_supplement) && selection[:single_supplement].present?
            end
          end

          if apply_restrictions?
            rate.min_stay = restriction_values[:min_stay]
            rate.max_stay = restriction_values[:max_stay]
            rate.closed_to_arrival = restriction_values[:closed_to_arrival]
            rate.closed_to_departure = restriction_values[:closed_to_departure]
            rate.stop_sell = restriction_values[:stop_sell]
          end
          rate.price ||= room_type.base_price if target_currency == hotel.default_currency
          next if rate.price.blank?
          rate.save!

          next unless changed_rate?(old_values, rate)

          hotel.inventory_audit_logs.create!(
            room_type: room_type,
            user: user,
            action_type: "rate_update",
            old_value: old_values.merge(date: date, rate_plan_id: rate_plan.id, currency: target_currency),
            new_value: {
              date: date,
              rate_plan_id: rate_plan.id,
              currency: target_currency,
              price: rate.price.to_f,
              walk_in_price: rate.walk_in_price&.to_f,
              corporate_price: rate.corporate_price&.to_f,
              ota_price: rate.ota_price&.to_f,
              min_stay: rate.min_stay,
              max_stay: rate.max_stay,
              closed_to_arrival: rate.closed_to_arrival,
              closed_to_departure: rate.closed_to_departure,
              stop_sell: rate.stop_sell,
              base_occupancy: rate.base_occupancy,
              extra_pax_charge: rate.extra_pax_charge&.to_f,
              single_supplement: rate.single_supplement&.to_f
            },
            metadata: { source: "inventory_dashboard_selection", rate_tier: tier || "online" }
          )
        end
      end
    end

    def target_currencies_for(rate_plan, date)
      return [ currency ] if apply_rates?
      return [ currency ] unless apply_restrictions?

      # If we are applying restrictions, we must apply them to ALL currencies
      # that this hotel has ever used to avoid discrepancies between currency views.
      existing_currencies = rate_plan.room_rates.where(date: date).distinct.pluck(:currency)
      (existing_currencies + [ currency, rate_plan.currency ]).compact.uniq
    end

    def room_numbers_for(room_type)
      return nil unless room_types.count == 1
      return nil if selected_room_numbers.blank?

      selected_room_numbers & room_type.room_numbers
    end

    def occupied_room_count(date, room_numbers)
      hotel.bookings.revenue_generating
           .joins(:booking_rooms)
           .where(":date >= bookings.check_in::date AND :date < bookings.check_out::date", date: date)
           .where(booking_rooms: { room_number: room_numbers })
           .distinct
           .count(:id)
    end

    def sync_to_channel_manager
      return if hotel.preferred_channel_manager.blank?

      ChannelManagers::SyncJob.perform_later(
        hotel.id,
        start_date,
        end_date,
        sync_availability: apply_inventory?,
        sync_rates: apply_rates?,
        sync_restrictions: apply_restrictions?
      )
    end

    def changed_rate?(old_values, rate)
      old_values[:price] != rate.price.to_f ||
        old_values[:walk_in_price] != rate.walk_in_price&.to_f ||
        old_values[:corporate_price] != rate.corporate_price&.to_f ||
        old_values[:ota_price] != rate.ota_price&.to_f ||
        old_values[:min_stay] != rate.min_stay ||
        old_values[:max_stay] != rate.max_stay ||
        old_values[:closed_to_arrival] != rate.closed_to_arrival ||
        old_values[:closed_to_departure] != rate.closed_to_departure ||
        old_values[:stop_sell] != rate.stop_sell ||
        old_values[:base_occupancy] != rate.base_occupancy ||
        old_values[:extra_pax_charge] != rate.extra_pax_charge&.to_f ||
        old_values[:single_supplement] != rate.single_supplement&.to_f
    end

    def cast_boolean(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def success
      { success: true }
    end

    def failure(message)
      { success: false, error: message }
    end
  end
end
