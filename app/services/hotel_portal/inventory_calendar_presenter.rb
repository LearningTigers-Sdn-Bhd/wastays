# frozen_string_literal: true

require "ostruct"

module HotelPortal
  class InventoryCalendarPresenter
    Row = Struct.new(:key, :kind, :room_type, :rate_plan, :channel_rate_plan_id, :channel, keyword_init: true) do
      def room_type_id = room_type.id
      def rate_plan_id = rate_plan&.id
      def label = room_type.name
      def sublabel
        case kind
        when :walk_in then "Walk-in Rate"
        when :corporate then "Corporate Rate"
        when :channel_availability then "#{channel['attributes']['channel']} (#{channel['attributes']['title']})"
        when :channel_rate then "#{channel['attributes']['channel']} (#{channel['attributes']['title']})"
        when :channel_summary then "OTA Channels"
        else "#{rate_plan&.name}"
        end
      end
      def inventory_row? = kind == :availability
      def rate_row? = kind == :rate
      def walk_in_row? = kind == :walk_in
      def corporate_row? = kind == :corporate
      def channel_availability_row? = kind == :channel_availability
      def channel_rate_row? = kind == :channel_rate
      def channel_summary_row? = kind == :channel_summary
    end

    attr_reader :hotel, :start_date, :end_date, :display_currency

    def initialize(hotel:, start_date:, end_date:, display_currency:, room_type_id: nil, rate_plan_id: nil)
      RoomRate.reset_column_information
      ChannelRoomRate.reset_column_information
      @hotel = hotel
      @start_date = start_date.to_date
      @end_date = end_date.to_date
      @display_currency = CurrencyCatalog.valid?(display_currency) ? CurrencyCatalog.normalize(display_currency) : default_currency
      @selected_room_type_id = room_type_id.presence&.to_i
      @selected_rate_plan_id = rate_plan_id.presence&.to_i
    end

    def dates
      @dates ||= (start_date..end_date).to_a
    end

    def connected_channels
      @connected_channels ||= Rails.cache.fetch("channex:channels:#{hotel.id}", expires_in: 10.minutes) do
        if hotel.preferred_channel_manager == "channex"
          begin
            client = Channex::Client.new
            property_id = hotel.channel_mapping&.external_id
            if property_id.present? && property_id != "pending"
              response = client.get("/channels")
              if response["data"].is_a?(Array)
                response["data"].select do |channel|
                  properties_data = channel.dig("relationships", "properties", "data")
                  properties_data.is_a?(Array) && properties_data.any? { |p| p["id"] == property_id }
                end
              else
                []
              end
            else
              []
            end
          rescue => e
            Rails.logger.error "Failed to fetch connected channels from Channel Manager: #{e.message}"
            []
          end
        else
          []
        end
      end
    end

    def channel_rates_by_key
      @channel_rates_by_key ||= ChannelRoomRate.where(
        room_type_id: active_room_type_ids,
        date: start_date..end_date,
        currency: default_currency
      ).each_with_object({}) do |crr, memo|
        if crr.rate_plan_id.present?
          key = "rtrp-#{crr.room_type_id}-#{crr.rate_plan_id}-#{crr.channel_rate_plan_id}-#{crr.date}"
          memo[key] = crr
        else
          key = "rt-#{crr.room_type_id}-#{crr.channel_id}-#{crr.date}"
          memo[key] = crr
        end
      end
    end

    def rows
      @rows ||= visible_room_types.flat_map do |room_type|
        inventory_row = Row.new(key: "room-#{room_type.id}-inventory", kind: :availability, room_type: room_type)

        mapped_channels = connected_channels.select do |channel|
          room_type_mapped_to_channel?(room_type, channel)
        end

        summary_rows = if mapped_channels.any?
          [ Row.new(key: "room-#{room_type.id}-summary", kind: :channel_summary, room_type: room_type) ]
        else
          []
        end

        # Collapsible connected OTAs under room inventory row
        inventory_sub_rows = mapped_channels.map do |channel|
          Row.new(
            key: "room-#{room_type.id}-inventory-channel-#{channel['id']}",
            kind: :channel_availability,
            room_type: room_type,
            channel: channel
          )
        end

        walk_in_row = Row.new(key: "room-#{room_type.id}-walk-in", kind: :walk_in, room_type: room_type)
        corporate_row = Row.new(key: "room-#{room_type.id}-corporate", kind: :corporate, room_type: room_type)

        rate_and_sub_rows = rate_plans_for(room_type).flat_map do |rate_plan|
          parent_row = Row.new(key: "room-#{room_type.id}-rate-#{rate_plan.id}", kind: :rate, room_type: room_type, rate_plan: rate_plan)

          sub_rows = []
          rtrp = room_type.room_type_rate_plans.find_by(rate_plan: rate_plan)
          ext_rp_id = rtrp&.channel_mapping&.external_id

          if ext_rp_id.present? && ext_rp_id != "pending"
            connected_channels.each do |channel|
              chan_rate_plans = channel.dig("attributes", "rate_plans") || []
              chan_rate_plans.each do |crp|
                if crp["rate_plan_id"] == ext_rp_id
                  sub_rows << Row.new(
                    key: "room-#{room_type.id}-rate-#{rate_plan.id}-channel-#{crp['id']}",
                    kind: :channel_rate,
                    room_type: room_type,
                    rate_plan: rate_plan,
                    channel_rate_plan_id: crp["id"],
                    channel: channel
                  )
                end
              end
            end
          end

          [ parent_row ] + sub_rows
        end

        [ inventory_row ] + summary_rows + inventory_sub_rows + rate_and_sub_rows + [ walk_in_row, corporate_row ]
      end
    end

    def room_type_options
      @room_type_options ||= hotel.room_types.order(:id).to_a
    end

    def rate_plan_options_struct
      @rate_plan_options_struct ||= visible_room_types.flat_map do |room_type|
        plans = rate_plans_for(room_type).map do |rate_plan|
          OpenStruct.new(label: "#{room_type.name} - #{rate_plan.name}", id: rate_plan.id, room_type_id: room_type.id, kind: :standard)
        end

        # Virtual Pricing Tiers, written onto the anchor plan's rate rows.
        tiers = [
          OpenStruct.new(label: "#{room_type.name} - Walk-in Rate", id: "tier_walk_in_#{room_type.id}", room_type_id: room_type.id, kind: :tier),
          OpenStruct.new(label: "#{room_type.name} - Corporate Rate", id: "tier_corporate_#{room_type.id}", room_type_id: room_type.id, kind: :tier)
        ]

        plans + tiers
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
      elsif row.channel_summary_row?
        channel_summary_cell(row.room_type, date)
      elsif row.channel_availability_row?
        channel_availability_cell(row.room_type, row.channel, date)
      elsif row.walk_in_row?
        tier_cell(row.room_type, date, :walk_in)
      elsif row.corporate_row?
        tier_cell(row.room_type, date, :corporate)
      elsif row.channel_rate_row?
        channel_rate_cell(row.room_type, row.rate_plan, row.channel_rate_plan_id, row.channel, date)
      else
        rate_cell(row.room_type, row.rate_plan, date)
      end
    end

    def channel_summary_cell(room_type, date)
      mapped_channels = connected_channels.select do |channel|
        room_type_mapped_to_channel?(room_type, channel)
      end
      total = mapped_channels.size
      open_count = 0
      channels_status = mapped_channels.map do |channel|
        cell = channel_availability_cell(room_type, channel, date)
        is_open = !cell[:closed]
        open_count += 1 if is_open
        {
          channel_id: channel["id"],
          channel_name: channel["attributes"]["title"],
          color: channel_color_for(channel["attributes"]["channel"]),
          short: channel_short_for(channel["attributes"]["channel"]),
          open: is_open
        }
      end

      {
        date: date,
        total: total,
        open_count: open_count,
        channels: channels_status
      }
    end

    def channel_color_for(channel_name)
      case channel_name.to_s.downcase
      when /booking/ then "bg-blue-600"
      when /expedia/ then "bg-yellow-500"
      when /agoda/ then "bg-red-500"
      when /airbnb/ then "bg-pink-500"
      when /hotels/ then "bg-rose-600"
      when /trip/ then "bg-sky-500"
      when /google/ then "bg-emerald-600"
      else "bg-slate-400"
      end
    end

    def channel_short_for(channel_name)
      case channel_name.to_s.downcase
      when /booking/ then "B"
      when /expedia/ then "E"
      when /agoda/ then "A"
      when /airbnb/ then "Ab"
      when /hotels/ then "H"
      when /trip/ then "T"
      when /google/ then "G"
      else channel_name.to_s[0..1].capitalize
      end
    end

    def empty_message
      return "No room types found. Add a room category before managing availability." if room_type_options.empty?

      "No room or rate-plan rows match this filter."
    end

    private

    def room_type_mapped_to_channel?(room_type, channel)
      ext_rt_id = room_type.channel_mapping&.external_id
      return false if ext_rt_id.blank? || ext_rt_id.to_s.start_with?("pending")

      mapping_settings = channel.dig("attributes", "settings", "mappingSettings") || channel.dig("attributes", "settings", "mapping_settings") || {}
      rooms = mapping_settings["rooms"] || mapping_settings[:rooms] || {}
      rooms.values.include?(ext_rt_id)
    end

    def tier_cell(room_type, date, tier_type)
      # walk_in_price/corporate_price live on the anchor plan's rate rows, which
      # is where ApplyInventoryDashboardSelection writes them.
      rate_plan = room_type.standard_rate_plan
      return { date: date } if rate_plan.blank?

      rate = rate_for(room_type, rate_plan, date)

      actual_price = case tier_type
      when :walk_in then rate&.walk_in_price
      when :corporate then rate&.corporate_price
      end

      price = actual_price.presence || rate&.price || room_type.base_price
      native_currency = default_currency

      display_conversion = display_conversion_for(price, from: native_currency)
      conversion_missing = price.present? && display_currency != native_currency && display_conversion.nil?

      display_price = display_conversion&.amount || price
      formatted_currency = (display_conversion.present? || conversion_missing) ? display_currency : native_currency

      {
        date: date,
        price: actual_price, # Original set price
        rate_plan_id: rate_plan.id,
        rate_tier: tier_type,
        formatted_price: format_price(display_price, formatted_currency),
        currency: native_currency,
        display_currency: formatted_currency,
        estimated: display_conversion.present? && native_currency != formatted_currency,
        conversion_missing: conversion_missing,
        is_modified: actual_price.present?,
        sell_mode: rate_plan&.sell_mode || "per_room",
        restriction_badges: [],
        restriction_compact: nil
      }
    end

    def sold_counts_by_room_type
      @sold_counts_by_room_type ||= begin
        counts = hotel.bookings.revenue_generating
                      .joins(:booking_rooms)
                      .where(booking_rooms: { room_type_id: active_room_type_ids })
                      .where("check_in::date < :end_date AND check_out::date > :start_date", start_date: start_date, end_date: end_date + 1.day)
                      .group("booking_rooms.room_type_id", "check_in", "check_out")
                      .count

        # Expand the counts per date
        result = Hash.new { |h, k| h[k] = Hash.new(0) }
        counts.each do |(room_type_id, b_start, b_end), count|
          (b_start.to_date...b_end.to_date).each do |date|
            next unless date >= start_date && date <= end_date
            result[room_type_id][date] += count
          end
        end
        result
      end
    end

    def default_currency
      hotel.default_currency.presence || "MYR"
    end

    def visible_room_types
      @visible_room_types ||= begin
        scope = hotel.room_types.includes(:rate_plans).order(:id)
        scope = scope.where(id: selected_room_type_id) if selected_room_type_id.present?
        scope.to_a
      end
    end

    # Special tiers get their own rows and are written through the anchor plan,
    # so they never appear as ordinary rate rows. Identified by kind rather than
    # by name: renaming "Walk-in Rate" used to turn it into an ordinary row that
    # the walk-in row still read from, and naming an ordinary plan "Corporate"
    # used to hide it from the grid while it stayed bookable.
    #
    # Archived plans are excluded to match the booking side, which offers only
    # RatePlan.active — showing rows the operator can edit and push to channels
    # for a plan no guest can book is worse than not showing them.
    def rate_plans_for(room_type)
      plans = room_type.rate_plans.sort_by(&:id)
      plans = plans.reject { |rate_plan| rate_plan.special_tier? || rate_plan.archived? }
      plans = plans.select { |rate_plan| rate_plan.id == selected_rate_plan_id } if selected_rate_plan_id.present?
      plans
    end

    def inventories_by_room_type
      @inventories_by_room_type ||= RoomInventory
        .where(room_type_id: visible_room_type_ids, date: start_date..end_date)
        .group_by(&:room_type_id)
        .transform_values { |inventories| inventories.index_by(&:date) }
    end

    # Keyed by [room_type_id, rate_plan_id], because a rate plan shared across
    # several categories holds one row per category per date — room_rates is
    # unique on (room_type_id, rate_plan_id, date, currency). Keying on the plan
    # alone let index_by(&:date) collapse the categories down to whichever row
    # the database returned last, so every category on a shared plan rendered
    # that one category's price and restrictions.
    #
    # Loads every plan for the visible categories, not just the filtered ones,
    # so tier rows (walk-in/corporate) still resolve when the grid is filtered
    # to a single plan.
    def rates_by_room_type_and_plan
      @rates_by_room_type_and_plan ||= RoomRate
        .where(room_type_id: visible_room_type_ids, date: start_date..end_date, currency: default_currency)
        .group_by { |rate| [ rate.room_type_id, rate.rate_plan_id ] }
        .transform_values { |rates| rates.index_by(&:date) }
    end

    def rate_for(room_type, rate_plan, date)
      rates_by_room_type_and_plan.dig([ room_type.id, rate_plan.id ], date)
    end

    # Indexed once: channel_rate_cell runs per channel rate plan per date, and
    # looked this up on every one of those cells.
    def derived_settings_by_channel_id
      @derived_settings_by_channel_id ||= hotel.channel_derived_settings.index_by(&:channel_id)
    end

    def visible_room_type_ids
      @visible_room_type_ids ||= visible_room_types.map(&:id)
    end

    def inventory_cell(room_type, date)
      inventory = inventories_by_room_type.dig(room_type.id, date)
      quantity = inventory&.quantity || room_type.quantity
      persisted_status = inventory&.status || "open"
      sold_count = sold_counts_by_room_type.dig(room_type.id, date) || 0

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
        sold_count: sold_count,
        status: persisted_status,
        status_label: status_label,
        closed: status_label != "Open"
      }
    end

    def rate_cell(room_type, rate_plan, date)
      rate = rate_for(room_type, rate_plan, date)
      native_currency = default_currency
      price = rate&.price || (native_currency == default_currency ? room_type.base_price : nil)

      display_conversion = display_conversion_for(price, from: native_currency)

      # If conversion is requested but fails due to missing exchange rate
      conversion_missing = price.present? && display_currency != native_currency && display_conversion.nil?

      display_price = display_conversion&.amount || price
      formatted_currency = (display_conversion.present? || conversion_missing) ? display_currency : native_currency

      # Determine if price is modified compared to base
      is_modified = false
      if native_currency == default_currency && price.present?
        is_modified = (price.to_f != room_type.base_price.to_f)
      elsif price.present? && rate.present?
        is_modified = true
      end

      {
        date: date,
        price: price,
        formatted_price: format_price(display_price, formatted_currency),
        currency: native_currency,
        display_currency: formatted_currency,
        estimated: display_conversion.present? && native_currency != formatted_currency,
        conversion_missing: conversion_missing,
        is_modified: is_modified,
        min_stay: rate&.min_stay,
        max_stay: rate&.max_stay,
        closed_to_arrival: rate&.closed_to_arrival? || false,
        closed_to_departure: rate&.closed_to_departure? || false,
        stop_sell: rate&.stop_sell? || false,
        applied_rule_type: rate&.applied_rule_type,
        single_supplement: rate&.single_supplement || rate_plan.single_supplement,
        base_occupancy: rate&.base_occupancy || rate_plan.base_occupancy,
        extra_pax_charge: rate&.extra_pax_charge || rate_plan.extra_pax_charge,
        sell_mode: rate_plan.sell_mode,
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

    def display_conversion_for(price, from:)
      return nil if price.blank?
      return CurrencyConverter::Conversion.new(amount: price, rate: 1.to_d, source: "same_currency") if from == display_currency

      CurrencyConverter.convert(price, from: from, to: display_currency, hotel: hotel)
    end

    def format_price(price, currency = nil)
      return "-" if price.blank?
      currency ||= display_currency

      CurrencyFormatter.format(price, currency: currency, symbol: false)
    end

    def channel_availability_cell(room_type, channel, date)
      inventory = inventories_by_room_type.dig(room_type.id, date)
      quantity = inventory&.quantity || room_type.quantity
      persisted_status = inventory&.status || "open"
      sold_count = sold_counts_by_room_type.dig(room_type.id, date) || 0

      override_key = "rt-#{room_type.id}-#{channel['id']}-#{date}"
      override = channel_rates_by_key[override_key]

      channel_availability = override&.availability.presence || quantity
      channel_status = override&.stop_sell ? "closed" : persisted_status

      status_label = if channel_status == "closed"
        "Closed"
      elsif channel_availability.to_i <= 0
        "Sold Out"
      else
        "Open"
      end

      {
        date: date,
        quantity: channel_availability,
        sold_count: sold_count,
        status: channel_status,
        status_label: status_label,
        closed: status_label != "Open",
        is_channel_override: true,
        channel_id: channel["id"]
      }
    end

    def channel_rate_cell(room_type, rate_plan, channel_rate_plan_id, channel, date)
      parent_rate = rate_for(room_type, rate_plan, date)
      native_currency = default_currency

      override_key = "rtrp-#{room_type.id}-#{rate_plan.id}-#{channel_rate_plan_id}-#{date}"
      override = channel_rates_by_key[override_key]

      price = override&.price.presence
      if price.blank? && (parent_rate&.price || room_type.base_price)
        base_val = parent_rate&.price || room_type.base_price
        derived_setting = derived_settings_by_channel_id[channel["id"]]
        if derived_setting
          case derived_setting.pricing_mode
          when "multiplier"
            price = base_val * (1 + derived_setting.pricing_value.to_d / 100)
          when "offset"
            price = base_val + derived_setting.pricing_value.to_d
          else
            price = base_val
          end
        else
          price = base_val
        end
      end

      display_conversion = display_conversion_for(price, from: native_currency)
      conversion_missing = price.present? && display_currency != native_currency && display_conversion.nil?

      display_price = display_conversion&.amount || price
      formatted_currency = (display_conversion.present? || conversion_missing) ? display_currency : native_currency

      is_modified = override&.price.present?

      min_stay = override ? override.min_stay : parent_rate&.min_stay
      max_stay = override ? override.max_stay : parent_rate&.max_stay
      closed_to_arrival = override ? (override.closed_to_arrival? || false) : (parent_rate&.closed_to_arrival? || false)
      closed_to_departure = override ? (override.closed_to_departure? || false) : (parent_rate&.closed_to_departure? || false)
      stop_sell = override ? (override.stop_sell? || false) : (parent_rate&.stop_sell? || false)

      {
        date: date,
        price: override&.price,
        parent_price: parent_rate&.price || room_type.base_price,
        formatted_price: format_price(display_price, formatted_currency),
        currency: native_currency,
        display_currency: formatted_currency,
        estimated: display_conversion.present? && native_currency != formatted_currency,
        conversion_missing: conversion_missing,
        is_modified: is_modified,
        min_stay: min_stay,
        max_stay: max_stay,
        closed_to_arrival: closed_to_arrival,
        closed_to_departure: closed_to_departure,
        stop_sell: stop_sell,
        single_supplement: parent_rate&.single_supplement || rate_plan.single_supplement,
        base_occupancy: parent_rate&.base_occupancy || rate_plan.base_occupancy,
        extra_pax_charge: parent_rate&.extra_pax_charge || rate_plan.extra_pax_charge,
        sell_mode: rate_plan.sell_mode,
        restriction_badges: channel_restriction_badges(min_stay, max_stay, closed_to_arrival, closed_to_departure, stop_sell),
        restriction_compact: channel_restriction_compact(min_stay, max_stay, closed_to_arrival, closed_to_departure, stop_sell),
        is_channel_override: true,
        channel_id: channel["id"],
        channel_rate_plan_id: channel_rate_plan_id
      }
    end

    def channel_restriction_badges(min_stay, max_stay, closed_to_arrival, closed_to_departure, stop_sell)
      badges = []
      badges << "Min #{min_stay}" if min_stay.present?
      badges << "Max #{max_stay}" if max_stay.present?
      badges << "CTA" if closed_to_arrival
      badges << "CTD" if closed_to_departure
      badges << "Stop Sell" if stop_sell
      badges
    end

    def channel_restriction_compact(min_stay, max_stay, closed_to_arrival, closed_to_departure, stop_sell)
      codes = []
      codes << "MIN#{min_stay}" if min_stay.present?
      codes << "MAX#{max_stay}" if max_stay.present?
      codes << "CTA" if closed_to_arrival
      codes << "CTD" if closed_to_departure
      codes << "STOP" if stop_sell
      return nil if codes.empty?

      codes.join(" ")
    end
  end
end
