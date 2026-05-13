# frozen_string_literal: true

module HotelPortal
  class InventoryCalendarPresenter
    CURRENCIES = %w[MYR USD].freeze

    Row = Struct.new(:key, :kind, :room_type, :rate_plan, keyword_init: true) do
      def room_type_id = room_type.id
      def rate_plan_id = rate_plan&.id
      def label = room_type.name
      def sublabel = rate_plan&.name
      def inventory_row? = kind == :availability
      def rate_row? = kind == :rate
    end

    attr_reader :hotel, :start_date, :end_date, :display_currency

    def initialize(hotel:, start_date:, end_date:, display_currency:, room_type_id: nil, rate_plan_id: nil)
      @hotel = hotel
      @start_date = start_date.to_date
      @end_date = end_date.to_date
      @display_currency = CURRENCIES.include?(display_currency.to_s) ? display_currency.to_s : default_currency
      @selected_room_type_id = room_type_id.presence&.to_i
      @selected_rate_plan_id = rate_plan_id.presence&.to_i
    end

    def dates
      @dates ||= (start_date..end_date).to_a
    end

    def rows
      @rows ||= visible_room_types.flat_map do |room_type|
        inventory_row = Row.new(key: "room-#{room_type.id}-inventory", kind: :availability, room_type: room_type)
        rate_rows = rate_plans_for(room_type).map do |rate_plan|
          Row.new(key: "room-#{room_type.id}-rate-#{rate_plan.id}", kind: :rate, room_type: room_type, rate_plan: rate_plan)
        end

        [inventory_row] + rate_rows
      end
    end

    def room_type_options
      @room_type_options ||= hotel.room_types.order(:id).to_a
    end

    def rate_plan_options
      @rate_plan_options ||= hotel.room_types.includes(:rate_plans).order(:id).flat_map do |room_type|
        room_type.rate_plans.order(:id).map do |rate_plan|
          ["#{room_type.name} - #{rate_plan.name}", rate_plan.id]
        end
      end
    end

    def rate_plan_options_struct
      @rate_plan_options_struct ||= hotel.room_types.includes(:rate_plans).order(:id).flat_map do |room_type|
        room_type.rate_plans.order(:id).map do |rate_plan|
          OpenStruct.new(label: "#{room_type.name} - #{rate_plan.name}", id: rate_plan.id, room_type_id: room_type.id)
        end
      end
    end

    def selected_room_type_id
      @selected_room_type_id
    end

    def selected_rate_plan_id
      @selected_rate_plan_id
    end

    def active_rate_plan_ids
      rows.map(&:rate_plan_id).compact.uniq
    end

    def active_room_type_ids
      rows.map(&:room_type_id).compact.uniq
    end

    def cell_for(row, date)
      if row.inventory_row?
        inventory_cell(row.room_type, date)
      else
        rate_cell(row.room_type, row.rate_plan, date)
      end
    end

    def empty_message
      return "No room types found. Add a room category before managing availability." if room_type_options.empty?

      "No room or rate-plan rows match this filter."
    end

    private

    def default_currency
      hotel.default_currency.presence || "MYR"
    end

    def visible_room_types
      @visible_room_types ||= begin
        scope = hotel.room_types.includes(:room_inventories, rate_plans: :room_rates).order(:id)
        scope = scope.where(id: selected_room_type_id) if selected_room_type_id.present?
        scope.to_a
      end
    end

    def rate_plans_for(room_type)
      plans = room_type.rate_plans.sort_by(&:id)
      plans = plans.select { |rate_plan| rate_plan.id == selected_rate_plan_id } if selected_rate_plan_id.present?
      plans
    end

    def inventories_by_room_type
      @inventories_by_room_type ||= visible_room_types.each_with_object({}) do |room_type, memo|
        memo[room_type.id] = room_type.room_inventories.where(date: start_date..end_date).index_by(&:date)
      end
    end

    def rates_by_rate_plan
      @rates_by_rate_plan ||= visible_room_types.each_with_object({}) do |room_type, memo|
        rate_plans_for(room_type).each do |rate_plan|
          memo[rate_plan.id] = rate_plan.room_rates.where(date: start_date..end_date, currency: display_currency).index_by(&:date)
        end
      end
    end

    def inventory_cell(room_type, date)
      inventory = inventories_by_room_type.dig(room_type.id, date)
      quantity = inventory&.quantity || room_type.quantity
      persisted_status = inventory&.status || "open"
      status_label = if persisted_status == "closed"
        "Closed"
      elsif quantity.to_i <= 0
        "Sold Out"
      else
        "Open"
      end

      {
        date: date,
        quantity: quantity,
        status: persisted_status,
        status_label: status_label,
        closed: status_label != "Open"
      }
    end

    def rate_cell(room_type, rate_plan, date)
      rate = rates_by_rate_plan.dig(rate_plan.id, date)
      price = rate&.price || (display_currency == "MYR" ? room_type.base_price : nil)
      
      # Determine if price is modified compared to base
      is_modified = false
      if display_currency == "MYR" && price.present?
        is_modified = (price.to_f != room_type.base_price.to_f)
      elsif price.present? && rate.present?
        is_modified = true # For non-MYR, if a rate object exists, we consider it modified/custom
      end

      {
        date: date,
        price: price,
        formatted_price: format_price(price),
        currency: display_currency,
        is_modified: is_modified,
        min_stay: rate&.min_stay,
        max_stay: rate&.max_stay,
        closed_to_arrival: rate&.closed_to_arrival? || false,
        closed_to_departure: rate&.closed_to_departure? || false,
        stop_sell: rate&.stop_sell? || false,
        restriction_badges: restriction_badges(rate),
        restriction_compact: restriction_compact(rate)
      }
    end

    def restriction_badges(rate)
      return [] if rate.blank?

      badges = []
      badges << "Min #{rate.min_stay}" if rate.min_stay.present?
      badges << "Max #{rate.max_stay}" if rate.max_stay.present?
      badges << "CTA" if rate.closed_to_arrival?
      badges << "CTD" if rate.closed_to_departure?
      badges << "Stop Sell" if rate.stop_sell?
      badges
    end

    def restriction_compact(rate)
      return nil if rate.blank?

      codes = []
      codes << "MIN#{rate.min_stay}" if rate.min_stay.present?
      codes << "MAX#{rate.max_stay}" if rate.max_stay.present?
      codes << "CTA" if rate.closed_to_arrival?
      codes << "CTD" if rate.closed_to_departure?
      codes << "STOP" if rate.stop_sell?
      return nil if codes.empty?

      codes.join(" ")
    end

    def format_price(price)
      return "-" if price.blank?

      symbol = display_currency == "USD" ? "$" : "RM"
      "#{symbol}#{ActiveSupport::NumberHelper.number_to_rounded(price, precision: 2, delimiter: ',', strip_insignificant_zeros: true)}"
    end
  end
end
