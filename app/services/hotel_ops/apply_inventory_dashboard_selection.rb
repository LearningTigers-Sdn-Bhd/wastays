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
      return failure("Price is required when applying rates.") if apply_rates? && price.blank?

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
      @rate_plan_ids ||= Array(selection[:rate_plan_ids]).reject(&:blank?).map(&:to_i)
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
      rate_plans_for(room_type).find_each do |rate_plan|
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
              min_stay: rate.min_stay,
              max_stay: rate.max_stay,
              closed_to_arrival: rate.closed_to_arrival,
              closed_to_departure: rate.closed_to_departure,
              stop_sell: rate.stop_sell
            }

            # Apply price update.
            should_apply_price = apply_rates? && target_currency == currency
            rate.price = price if should_apply_price

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
                min_stay: rate.min_stay,
                max_stay: rate.max_stay,
                closed_to_arrival: rate.closed_to_arrival,
                closed_to_departure: rate.closed_to_departure,
                stop_sell: rate.stop_sell
              },
              metadata: { source: "inventory_dashboard_selection" }
            )
          end
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
           .where(":date >= bookings.check_in AND :date < bookings.check_out", date: date)
           .where(booking_rooms: { room_number: room_numbers })
           .distinct
           .count(:id)
    end

    def sync_to_channel_manager
      return if hotel.preferred_channel_manager.blank?

      ChannelManagers::SyncJob.perform_later(hotel.id, start_date, end_date)
    end

    def changed_rate?(old_values, rate)
      old_values[:price] != rate.price.to_f ||
        old_values[:min_stay] != rate.min_stay ||
        old_values[:max_stay] != rate.max_stay ||
        old_values[:closed_to_arrival] != rate.closed_to_arrival ||
        old_values[:closed_to_departure] != rate.closed_to_departure ||
        old_values[:stop_sell] != rate.stop_sell
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
