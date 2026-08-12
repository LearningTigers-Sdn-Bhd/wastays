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
      # A rate or restriction edit has to name its plans. An empty list used to
      # mean "every active plan in the category", which turned one unselected
      # field into a property-wide price change.
      if channel_id.blank? && (apply_rates? || apply_restrictions?) && rate_plan_ids.empty?
        return failure("Select at least one rate plan.")
      end
      return failure("Enter at least one price when applying rates.") if channel_id.blank? && apply_rates? && price.blank? && occupancy_prices.empty? && selection[:single_supplement].blank? && selection[:base_occupancy].blank? && selection[:extra_pax_charge].blank?
      return failure("Local occupancy and supplement fields don't apply to OTA channel rates.") if channel_id.present? && pax_fields_requested?

      ActiveRecord::Base.transaction do
        Thread.current[:skip_ari_sync] = true

        if channel_id.present?
          apply_channel_updates
        else
          room_types.each do |room_type|
            apply_inventory_to(room_type) if apply_inventory?
            apply_rates_to(room_type) if apply_rates? || apply_restrictions?
          end
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

    def channel_id
      selection[:channel_id].presence
    end

    def channel_rate_plan_id
      selection[:channel_rate_plan_id].presence
    end

    def pax_fields_requested?
      pax_fields = %w[base_occupancy extra_pax_charge single_supplement]

      if selection[:modified_fields].present?
        (Array(selection[:modified_fields]) & pax_fields).any?
      else
        pax_fields.any? { |field| selection.key?(field.to_sym) && selection[field.to_sym].present? }
      end
    end

    def apply_channel_updates
      room_types.each do |room_type|
        (start_date..end_date).each do |date|
          crr = room_type.channel_room_rates.find_or_initialize_by(
            rate_plan_id: rate_plan_ids.first.is_a?(Integer) ? rate_plan_ids.first : nil,
            channel_id: channel_id,
            channel_rate_plan_id: channel_rate_plan_id,
            date: date,
            currency: currency
          )

          if apply_inventory?
            crr.availability = quantity if selection.key?(:quantity)
            crr.stop_sell = (status == "closed") if selection.key?(:status)
          end

          if apply_rates?
            crr.price = price if selection.key?(:price) && price.present?
          end

          if apply_restrictions?
            crr.min_stay = restriction_values[:min_stay]
            crr.max_stay = restriction_values[:max_stay]
            crr.closed_to_arrival = restriction_values[:closed_to_arrival]
            crr.closed_to_departure = restriction_values[:closed_to_departure]
            crr.stop_sell = restriction_values[:stop_sell]
          end

          crr.save!
        end
      end
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

    def occupancy_prices
      @occupancy_prices ||= selection.fetch(:occupancy_prices, {}).to_h.each_with_object({}) do |(adults, amount), prices|
        next if amount.blank?

        prices[adults.to_s] = BigDecimal(amount.to_s)
      end
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
      # The selection always names its plans, so there is no all-plans fallback:
      # a list holding only OTA tier ids resolves to no plan and writes nothing.
      plans = room_type.rate_plans.active.where(id: rate_plan_ids.grep(Integer))

      anchor_restrictions_pending = false

      plans.find_each do |rate_plan|
        anchor_restrictions_pending ||= rate_plan.anchored?
        update_rates_for_plan(
          room_type,
          rate_plan,
          apply_price: apply_rates?,
          apply_plan_restrictions: apply_restrictions? && !rate_plan.anchored?
        )
      end

      # Walk-in and corporate keep their restrictions on the anchor, so selecting
      # both writes the same rows twice. Applied once, after the loop, or the
      # operator gets a duplicate audit entry for a single edit.
      return unless anchor_restrictions_pending && apply_restrictions?

      anchor = room_type.standard_rate_plan
      # If the anchor was itself in the selection the loop already wrote them.
      return if anchor.blank? || plans.exists?(id: anchor.id)

      update_rates_for_plan(room_type, anchor, apply_price: false, apply_plan_restrictions: true)
    end

    def update_rates_for_plan(room_type, rate_plan, apply_price:, apply_plan_restrictions:)
      # Ensure rate plan currency follows the requested currency when applying rates
      if apply_price && rate_plan.currency != currency
        rate_plan.update!(currency: currency)
      end

      (start_date..end_date).each do |date|
        target_currencies_for(rate_plan, date, room_type: room_type, apply_price:, apply_plan_restrictions:).each do |target_currency|
          rate = rate_plan.room_rates.find_or_initialize_by(date: date, currency: target_currency, room_type: room_type)
          old_values = {
            price: rate.price&.to_f,
            min_stay: rate.min_stay,
            max_stay: rate.max_stay,
            closed_to_arrival: rate.closed_to_arrival,
            closed_to_departure: rate.closed_to_departure,
            stop_sell: rate.stop_sell,
            base_occupancy: rate.base_occupancy,
            extra_pax_charge: rate.extra_pax_charge&.to_f,
            single_supplement: rate.single_supplement&.to_f,
            occupancy_prices: rate.occupancy_prices
          }

          # Apply price update.
          should_apply_price = apply_price && target_currency == currency
          if should_apply_price
            rate.price = price if selection[:price].present?

            # Apply per-pax rules
            if selection[:modified_fields].present?
              rate.base_occupancy = base_occupancy if selection[:modified_fields].include?("base_occupancy")
              rate.extra_pax_charge = extra_pax_charge if selection[:modified_fields].include?("extra_pax_charge")
              rate.single_supplement = single_supplement if selection[:modified_fields].include?("single_supplement")
              rate.occupancy_prices = occupancy_prices_for(room_type) if selection[:modified_fields].include?("occupancy_prices")
            else
              rate.base_occupancy = base_occupancy if selection.key?(:base_occupancy) && selection[:base_occupancy].present?
              rate.extra_pax_charge = extra_pax_charge if selection.key?(:extra_pax_charge) && selection[:extra_pax_charge].present?
              rate.single_supplement = single_supplement if selection.key?(:single_supplement) && selection[:single_supplement].present?
              rate.occupancy_prices = occupancy_prices_for(room_type) if occupancy_prices.any?
            end
          end

          if apply_plan_restrictions
            rate.min_stay = restriction_values[:min_stay]
            rate.max_stay = restriction_values[:max_stay]
            rate.closed_to_arrival = restriction_values[:closed_to_arrival]
            rate.closed_to_departure = restriction_values[:closed_to_departure]
            rate.stop_sell = restriction_values[:stop_sell]
          end
          if rate.price.blank? && rate.occupancy_prices.present?
            rate.price = rate.occupancy_prices[room_type.max_adults.to_s] || rate.occupancy_prices.values.last
          end
          rate.price ||= resting_price_for(room_type, rate_plan, date, target_currency) if target_currency == hotel.default_currency
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
              stop_sell: rate.stop_sell,
              base_occupancy: rate.base_occupancy,
              extra_pax_charge: rate.extra_pax_charge&.to_f,
                single_supplement: rate.single_supplement&.to_f,
              occupancy_prices: rate.occupancy_prices
            },
            metadata: { source: "inventory_dashboard_selection", rate_kind: rate_plan.kind }
          )
        end
      end
    end

    # room_rates.price is NOT NULL, so applying a restriction to a date with no
    # row yet has to write some price alongside it. That price has to be the one
    # the plan was already selling at, or the restriction silently repriced the
    # date.
    #
    # It used to be room_type.base_price unconditionally. For a plan deriving its
    # price from the anchor (RoomTypeRatePlan multiplier/offset) that is the
    # wrong number, and writing it is permanent: BookingEngine and
    # CalculateStayPrice only derive while no explicit row exists, so a min-stay
    # would drop a +20% plan back to the anchor for that date, for good.
    def resting_price_for(room_type, rate_plan, date, target_currency)
      Rates::ResolveEffectiveNightlyPrice.call(
        room_type: room_type,
        rate_plan: rate_plan,
        date: date,
        currency: target_currency,
        adults: rate_plan.sell_mode == "per_person" ? room_type.max_adults : 2,
        room_type_rate_plan: room_type_rate_plan_for(room_type, rate_plan)
      ).base_amount
    end

    def room_type_rate_plan_for(room_type, rate_plan)
      @room_type_rate_plans ||= {}
      @room_type_rate_plans[[ room_type.id, rate_plan.id ]] ||=
        room_type.room_type_rate_plans.find_by(rate_plan: rate_plan)
    end

    def target_currencies_for(rate_plan, date, room_type:, apply_price:, apply_plan_restrictions:)
      return [ currency ] if apply_price
      return [ currency ] unless apply_plan_restrictions

      # If we are applying restrictions, we must apply them to ALL currencies
      # that this hotel has ever used to avoid discrepancies between currency views.
      existing_currencies = rate_plan.room_rates.where(date: date, room_type: room_type).distinct.pluck(:currency)
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
        old_values[:min_stay] != rate.min_stay ||
        old_values[:max_stay] != rate.max_stay ||
        old_values[:closed_to_arrival] != rate.closed_to_arrival ||
        old_values[:closed_to_departure] != rate.closed_to_departure ||
        old_values[:stop_sell] != rate.stop_sell ||
        old_values[:base_occupancy] != rate.base_occupancy ||
        old_values[:extra_pax_charge] != rate.extra_pax_charge&.to_f ||
        old_values[:single_supplement] != rate.single_supplement&.to_f ||
        old_values[:occupancy_prices] != rate.occupancy_prices
    end

    def occupancy_prices_for(room_type)
      occupancy_prices.select { |adults, _amount| adults.to_i <= room_type.max_adults.to_i }
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
