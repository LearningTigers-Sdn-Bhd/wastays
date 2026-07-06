# frozen_string_literal: true

require "ostruct"

module ChannelManagers
  class ChannexAdapter < BaseAdapter
    def onboard_hotel
      client = Channex::Client.new

      # 1. Create Property
      property_id = ensure_property(client)
      return failure("Failed to create Channel Manager property. Check logs for details.") unless property_id

      # 2. Create Room Types
      @hotel.room_types.each do |room_type|
        rt_id = sync_room_type(room_type)
        return failure("Failed to create Channel Manager room type: #{room_type.name}") unless rt_id
      end

      # 3. Create Rate Plans (for each room type)
      @hotel.room_types.each do |room_type|
        result = ensure_rate_plans(client, room_type)
        return failure("Failed to create Channel Manager rate plans for: #{room_type.name}") unless result
      end

      success("Hotel onboarded to Channel Manager")
    rescue StandardError => e
      failure("Onboarding error: #{e.message}")
    end

    def sync_hotel
      client = Channex::Client.new
      ensure_property(client)
    end

    def connected_channels
      client = Channex::Client.new
      property_mapping = mapping_for(@hotel)
      return [] if property_mapping.nil? || property_mapping.external_id == "pending"

      property_id = property_mapping.external_id

      Rails.cache.fetch("channex:channels:#{@hotel.id}", expires_in: 10.minutes) do
        response = client.get("/channels")
        if response["data"].is_a?(Array)
          response["data"].select do |channel|
            properties_data = channel.dig("relationships", "properties", "data")
            properties_data.is_a?(Array) && properties_data.any? { |p| p["id"] == property_id }
          end
        else
          []
        end
      end rescue []
    end

    def sync_room_type(room_type)
      client = Channex::Client.new
      property_id = mapping_for(@hotel).external_id
      mapping = mapping_for(room_type)

      payload = {
        room_type: {
          property_id: property_id,
          title: room_type.name,
          count_of_rooms: room_type.quantity,
          occ_adults: room_type.max_adults,
          occ_children: room_type.max_children || 0,
          occ_infants: 0,
          default_occupancy: room_type.max_adults,
          facilities: map_amenities_to_channex_ids(room_type.amenities, :room)
        }
      }

      response = if mapping.external_id == "pending"
                   client.post("/room_types", payload)
      else
                   client.put("/room_types/#{mapping.external_id}", payload)
      end

      if response["data"] && response["data"]["id"]
        mapping.update!(external_id: response["data"]["id"])
        response["data"]["id"]
      else
        Rails.logger.error "Channel Manager Room Type Sync Failed (#{room_type.name}): #{response}"
        nil
      end
    end

    def sync_rate_plan(rate_plan, room_type: nil)
      client = Channex::Client.new
      property_id = mapping_for(@hotel).external_id

      # If no room_type is provided, we use the first one as a fallback
      # This matches the "master plan" logic used in other parts of the system
      room_type ||= rate_plan.room_types.first
      return nil if room_type.blank?

      room_type_id = mapping_for(room_type).external_id
      room_type_rate_plan = room_type.room_type_rate_plans.find_by(rate_plan: rate_plan)
      return nil if room_type_rate_plan.blank?
      mapping = mapping_for(room_type_rate_plan)

      payload = {
        rate_plan: {
          property_id: property_id,
          room_type_id: room_type_id,
          title: "#{rate_plan.name} (#{room_type.name})",
          currency: rate_plan.currency,
          sell_mode: rate_plan.sell_mode,
          options: default_rate_plan_options(rate_plan, room_type: room_type)
        }
      }

      response = if mapping.external_id == "pending"
                   client.post("/rate_plans", payload)
      else
                   client.put("/rate_plans/#{mapping.external_id}", payload)
      end

      if response["data"] && response["data"]["id"]
        mapping.update!(external_id: response["data"]["id"])
        response["data"]["id"]
      else
        Rails.logger.error "Channel Manager Rate Plan Sync Failed (#{rate_plan.name}): #{response}"
        nil
      end
    end

    def delete_room_type(external_id)
      client = Channex::Client.new
      client.delete("/room_types/#{external_id}")
    end

    def delete_rate_plan(external_id)
      client = Channex::Client.new
      client.delete("/rate_plans/#{external_id}")
    end

    def push_ari(date_range:, sync_availability: true, sync_rates: true, sync_restrictions: true, room_type_ids: nil, rate_plan_ids: nil, rate_plan_fields: nil)
      client = Channex::Client.new
      property_id = mapping_for(@hotel).external_id

      # 1. Push Availability (Room Type level)
      if sync_availability
        availability_result = push_availability(client, property_id, date_range, room_type_ids: room_type_ids)
        return failure(availability_result[:message]) unless availability_result[:ok]
      end

      # 2. Push Restrictions/Rates (Rate Plan level)
      if sync_rates || sync_restrictions
        restrictions_result = push_restrictions(client, property_id, date_range, rate_plan_ids: rate_plan_ids, sync_rates: sync_rates, sync_restrictions: sync_restrictions, rate_plan_fields: rate_plan_fields)
        return failure(restrictions_result[:message]) unless restrictions_result[:ok]
      end

      success("ARI pushed to Channel Manager")
    end

    def push_booking(booking)
      client = Channex::Client.new
      property_id = mapping_for(@hotel).external_id

      payload = {
        booking: {
          property_id: property_id,
          ota_name: "WAStays (Manual)",
          status: "new",
          arrival_date: booking.check_in.to_date.to_s,
          departure_date: booking.check_out.to_date.to_s,
          amount: format("%.2f", booking.total_amount.to_f),
          currency: booking.currency,
          customer: {
            name: booking.guest_name,
            mail: booking.guest_email,
            phone: booking.guest_phone,
            country: booking.guest_country
          },
          rooms: booking.booking_rooms.group_by { |br| [ br.room_type_id, br.rate_plan_id ] }.map do |(room_type_id, rate_plan_id), rooms|
            br = rooms.first
            rp = br.rate_plan || br.room_type.rate_plans.first
            room_type_rate_plan = br.room_type.room_type_rate_plans.find_by(rate_plan: rp)
            {
              room_type_id: mapping_for(br.room_type).external_id,
              rate_plan_id: room_type_rate_plan ? mapping_for(room_type_rate_plan).external_id : nil,
              count: rooms.size,
              amount: format("%.2f", rooms.sum { |r| r.subtotal.to_f })
            }
          end
        }
      }

      response = client.post("/bookings", payload)

      if response["data"] && response["data"]["id"]
        Booking.transaction do
          old_value = booking.slice("channel_manager_reference", "revision_number")
          booking.update!(channel_manager_reference: response["data"]["id"], revision_number: response["data"]["revision_id"])
          Bookings::RecordAuditLog.call!(
            auditable: booking,
            action_type: "external_modification",
            source: "channel_manager",
            old_value: old_value,
            new_value: booking.slice("channel_manager_reference", "revision_number"),
            metadata: { "source" => "Channex", "external_reference" => response["data"]["id"] }
          )
        end
        success("Manual booking pushed to Channel Manager")
      else
        failure("CRS Sync failed: #{response[:details] || response['details'] || response}")
      end
    end

    def ingest_booking(payload:)
      # Channex can return data in two formats:
      # 1. Single revision: { "data": { "arrival_date": "...", ... } }
      # 2. List item: { "attributes": { "arrival_date": "...", ... }, "id": "..." }

      raw_data = payload["data"] || payload
      attributes = raw_data["attributes"] || raw_data

      wa_status = case attributes["status"]
      when "cancelled" then "cancelled"
      else "confirmed"
      end

      # Extract dates with multiple fallbacks
      check_in = attributes["arrival_date"] || attributes["checkin_date"]
      check_out = attributes["departure_date"] || attributes["checkout_date"]

      # If still missing, check the first room (common in some Channex payloads)
      if check_in.blank? && attributes["rooms"]&.any?
        first_room = attributes["rooms"].first
        check_in ||= first_room["arrival_date"] || first_room["checkin_date"]
        check_out ||= first_room["departure_date"] || first_room["checkout_date"]
      end

      # Extract revision number
      # Some Channex payloads have a numeric revision_id, others only have a UUID id.
      # To ensure ordering and duplicate detection in our integer revision_number column,
      # we fallback to a timestamp-based integer if revision_id is not a number.
      revision_val = attributes["revision_id"] || attributes["id"]
      numeric_revision = if revision_val.to_s =~ /^\d+$/
        revision_val.to_i
      else
        safe_parse_datetime(attributes["inserted_at"]).to_i
      end

      {
        hotel: @hotel,
        external_reference: attributes["ota_reservation_id"] || attributes["unique_id"] || attributes["id"],
        channel_manager_reference: attributes["booking_id"] || attributes["id"],
        revision_number: numeric_revision,
        status: wa_status,
        check_in: safe_parse_date(check_in),
        check_out: safe_parse_date(check_out),
        guest_details: {
          name: extract_guest_name(attributes),
          email: attributes.dig("customer", "email") || attributes.dig("customer", "mail"),
          phone: attributes.dig("customer", "phone") || attributes.dig("customer", "Telephone", "@PhoneNumber"),
          country: attributes.dig("customer", "country")
        },
        rooms: parse_booking_rooms(attributes["rooms"] || []),
        total_amount: attributes["amount"].to_f,
        currency: attributes["currency"] || "MYR",
        source: attributes["ota_name"] || "channex"
      }
    end

    private

    def parse_booking_rooms(rooms_data)
      rooms_data.map do |room|
        room_type = ChannelMapping.find_by(provider: provider_name, external_id: room["room_type_id"], mappable_type: "RoomType")&.mappable
        rtrp_mapping = ChannelMapping.find_by(provider: provider_name, external_id: room["rate_plan_id"], mappable_type: "RoomTypeRatePlan")
        rate_plan = rtrp_mapping&.mappable&.rate_plan

        {
          room_type: room_type,
          rate_plan: rate_plan,
          rate_plan_id: rate_plan&.id,
          quantity: room["count"] || 1,
          amount: room["amount"].to_f
        }
      end.compact
    end

    def extract_guest_name(attributes)
      given = attributes.dig("customer", "PersonName", "GivenName").to_s.strip
      surname = attributes.dig("customer", "PersonName", "Surname").to_s.strip
      full_name = [ given, surname ].reject(&:blank?).join(" ").strip

      return full_name if full_name.present?

      attributes.dig("customer", "name").to_s.strip.presence || "Guest"
    end

    def provider_name
      "channex"
    end

    def push_availability(client, property_id, date_range, room_type_ids: nil)
      values = push_availability_values(date_range, room_type_ids: room_type_ids)

      # Sync channel-specific availability rules (allotments/closeouts)
      sync_rt_ids = room_type_ids.is_a?(Hash) ? room_type_ids.keys.map(&:to_i) : (room_type_ids || @hotel.room_types.pluck(:id))
      sync_channel_availability_rules(client, property_id, date_range, sync_rt_ids)

      return { ok: true } if values.empty?

      response = client.post("/availability", { values: values })

      if response[:error] || response["error"]
        if response[:retryable] || response["retryable"]
          raise Channex::Client::RetryableRequestError, "Availability sync retryable failure: #{response[:details] || response['details'] || response}"
        end
        return { ok: false, message: "Availability sync failed: #{response[:details] || response['details'] || response}" }
      end

      # For Stage 2 Certification: Task IDs are in response["data"][0]["id"] (Array)
      # or response["data"]["id"] (Hash)
      data = response["data"]
      task_id = data.is_a?(Array) ? data.dig(0, "id") : data&.fetch("id", nil)

      Rails.logger.info "Channex Availability Task ID: #{task_id}" if task_id

      { ok: true, task_id: task_id }
    end

    def push_restrictions(client, property_id, date_range, rate_plan_ids: nil, sync_rates: true, sync_restrictions: true, rate_plan_fields: nil)
      values = push_restrictions_values(date_range, rate_plan_ids: rate_plan_ids, sync_rates: sync_rates, sync_restrictions: sync_restrictions, rate_plan_fields: rate_plan_fields)
      return { ok: true } if values.empty?

      response = client.post("/restrictions", { values: values })

      if response[:error] || response["error"]
        if response[:retryable] || response["retryable"]
          raise Channex::Client::RetryableRequestError, "Restrictions sync retryable failure: #{response[:details] || response['details'] || response}"
        end
        return { ok: false, message: "Restrictions sync failed: #{response[:details] || response['details'] || response}" }
      end

      # For Stage 2 Certification: Task IDs are in response["data"][0]["id"]
      data = response["data"]
      task_id = data.is_a?(Array) ? data.dig(0, "id") : data&.fetch("id", nil)

      Rails.logger.info "Channex Restrictions Task ID: #{task_id}" if task_id

      { ok: true, task_id: task_id }
    end

    def push_availability_values(date_range, room_type_ids: nil)
      values = []
      property_id = mapping_for(@hotel).external_id

      @hotel.room_types.each do |room_type|
        # Determine the effective range for this room type
        effective_range = if room_type_ids.is_a?(Hash) && (room_type_ids.key?(room_type.id.to_s) || room_type_ids.key?(room_type.id))
          win = room_type_ids[room_type.id.to_s] || room_type_ids[room_type.id]

          min_val = win.is_a?(Hash) ? (win["min"] || win[:min]) : win[0]
          max_val = win.is_a?(Hash) ? (win["max"] || win[:max]) : win[1]

          start_d = min_val.is_a?(Date) ? min_val : Date.parse(min_val.to_s)
          end_d = max_val.is_a?(Date) ? max_val : Date.parse(max_val.to_s)

          (start_d..end_d)
        elsif room_type_ids.is_a?(Array) && room_type_ids.include?(room_type.id)
          date_range
        elsif room_type_ids.nil?
          date_range
        else
          next # Not in sync scope
        end

        ext_rt_id = mapping_for(room_type).external_id
        next if ext_rt_id == "pending"

        current_range = nil
        inventories_by_date = room_type.room_inventories.where(date: effective_range).index_by(&:date)

        effective_range.each do |date|
          inventory = inventories_by_date[date]

          # During Full Sync (room_type_ids is nil), we ensure all dates in the range are covered.
          # For surgical updates, we only sync dates where a record exists.
          is_full_sync = room_type_ids.nil?
          next if inventory.nil? && !is_full_sync

          val_data = {
            property_id: property_id,
            room_type_id: ext_rt_id,
            availability: inventory&.quantity || 0
          }

          if current_range.nil?
            current_range = val_data.merge(date_from: date.to_s, date_to: date.to_s)
          elsif current_range.except(:date_from, :date_to) == val_data && Date.parse(current_range[:date_to]) + 1.day == date
            current_range[:date_to] = date.to_s
          else
            values << current_range
            current_range = val_data.merge(date_from: date.to_s, date_to: date.to_s)
          end
        end

        values << current_range if current_range.present?
      end
      values
    end

    def push_restrictions_values(date_range, rate_plan_ids: nil, sync_rates: true, sync_restrictions: true, rate_plan_fields: nil)
      values = []
      property_id = mapping_for(@hotel).external_id

      @hotel.room_types.each do |room_type|
        room_type.rate_plans.each do |rate_plan|
          # Determine the effective range for this rate plan
          effective_range = if rate_plan_ids.is_a?(Hash) && (rate_plan_ids.key?(rate_plan.id.to_s) || rate_plan_ids.key?(rate_plan.id))
            win = rate_plan_ids[rate_plan.id.to_s] || rate_plan_ids[rate_plan.id]

            min_val = win.is_a?(Hash) ? (win["min"] || win[:min]) : win[0]
            max_val = win.is_a?(Hash) ? (win["max"] || win[:max]) : win[1]

            start_d = min_val.is_a?(Date) ? min_val : Date.parse(min_val.to_s)
            end_d = max_val.is_a?(Date) ? max_val : Date.parse(max_val.to_s)

            (start_d..end_d)
          elsif rate_plan_ids.is_a?(Array) && rate_plan_ids.include?(rate_plan.id)
            date_range
          elsif rate_plan_ids.nil?
            date_range
          else
            next # Not in sync scope
          end

          room_type_rate_plan = room_type.room_type_rate_plans.find_by(rate_plan: rate_plan)
          next if room_type_rate_plan.blank?

          ext_rp_id = mapping_for(room_type_rate_plan).external_id
          next if ext_rp_id == "pending"

          # Determine which fields to include for this specific rate plan
          specific_fields = rate_plan_fields&.fetch(rate_plan.id.to_s, nil) || rate_plan_fields&.fetch(rate_plan.id, nil)

          # If we have specific fields, we ignore the general category flags for precision
          final_sync_rates = specific_fields ? (specific_fields.include?("price") || specific_fields.include?(:price)) : sync_rates
          final_sync_restrictions = if specific_fields
            # If specific fields exist, check if ANY restriction field is present
            (specific_fields.map(&:to_s) & [ "min_stay", "max_stay", "closed_to_arrival", "closed_to_departure", "stop_sell" ]).any?
          else
            sync_restrictions
          end

          current_range = nil
          rates_by_date = rate_plan.room_rates.where(date: effective_range, currency: rate_plan.currency).index_by(&:date)

          # Iterate over all dates in the effective range to ensure a full snapshot
          effective_range.each do |date|
            rate = rates_by_date[date]

            # During Full Sync (specific_fields is nil), we ensure all dates in the range are covered.
            # For surgical updates, we only sync dates where a record exists.
            is_full_restrictions_sync = sync_restrictions && specific_fields.nil?
            is_full_rates_sync = sync_rates && specific_fields.nil?
            next if rate.nil? && !is_full_restrictions_sync && !is_full_rates_sync

            val_data = {
              property_id: property_id,
              rate_plan_id: ext_rp_id
            }

            if final_sync_rates
              ota_price = rate&.price
              val_data[:rate] = format("%.2f", ota_price.to_f) if ota_price
            end

            if final_sync_restrictions
              # Map supported restrictions surgically
              if specific_fields
                s_fields = specific_fields.map(&:to_s)
                val_data[:min_stay_arrival] = rate.min_stay if s_fields.include?("min_stay") && rate.min_stay.present?
                val_data[:max_stay_arrival] = rate.max_stay if s_fields.include?("max_stay") && rate.max_stay.present?
                val_data[:closed_to_arrival] = rate.closed_to_arrival ? 1 : 0 if s_fields.include?("closed_to_arrival") && !rate.closed_to_arrival.nil?
                val_data[:closed_to_departure] = rate.closed_to_departure ? 1 : 0 if s_fields.include?("closed_to_departure") && !rate.closed_to_departure.nil?
                val_data[:stop_sell] = rate.stop_sell ? 1 : 0 if s_fields.include?("stop_sell") && !rate.stop_sell.nil?
              else
                # For Full Sync, we provide a full snapshot with defaults for each date and rate plan.
                # This ensures that any stale values in the channel manager are overwritten.
                val_data[:min_stay_arrival] = rate&.min_stay || 1
                val_data[:max_stay_arrival] = rate&.max_stay || 999
                val_data[:closed_to_arrival] = (rate&.closed_to_arrival ? 1 : 0)
                val_data[:closed_to_departure] = (rate&.closed_to_departure ? 1 : 0)
                val_data[:stop_sell] = (rate&.stop_sell ? 1 : 0)
              end
            end

            if current_range.nil?
              current_range = val_data.merge(date_from: date.to_s, date_to: date.to_s)
            elsif current_range.except(:date_from, :date_to) == val_data && Date.parse(current_range[:date_to]) + 1.day == date
              current_range[:date_to] = date.to_s
            else
              values << current_range
              current_range = val_data.merge(date_from: date.to_s, date_to: date.to_s)
            end
          end

          values << current_range if current_range.present?

          # --- Sync Channel-Specific Overrides for this rate plan ---
          if ext_rp_id.present? && ext_rp_id != "pending"
            channels_list = connected_channels

            channels_list.each do |channel|
              chan_rate_plans = channel.dig("attributes", "rate_plans") || []
              chan_rate_plans.each do |crp|
                next unless crp["rate_plan_id"] == ext_rp_id

                crp_id = crp["id"]
                overrides_by_date = ChannelRoomRate.where(
                  room_type_id: room_type.id,
                  rate_plan_id: rate_plan.id,
                  channel_rate_plan_id: crp_id,
                  date: effective_range,
                  currency: rate_plan.currency
                ).index_by(&:date)

                rates_by_date = rate_plan.room_rates.where(date: effective_range, currency: rate_plan.currency).index_by(&:date)

                current_crp_range = nil

                effective_range.each do |date|
                  override = overrides_by_date[date]
                  rate = rates_by_date[date]

                  # We only sync if an override exists or if we are doing a full sync
                  next if override.nil? && rate_plan_ids.nil?

                  val_data = {
                    property_id: property_id,
                    rate_plan_id: crp_id
                  }

                  if final_sync_rates
                    override_price = override&.price.presence
                    if override_price.blank? && rate&.price
                      derived_setting = @hotel.channel_derived_settings.find_by(channel_id: channel["id"])
                      if derived_setting
                        case derived_setting.pricing_mode
                        when "multiplier"
                          override_price = rate.price * (1 + derived_setting.pricing_value.to_d / 100)
                        when "offset"
                          override_price = rate.price + derived_setting.pricing_value.to_d
                        else
                          override_price = rate.price
                        end
                      else
                        override_price = rate.price
                      end
                    end
                    val_data[:rate] = format("%.2f", override_price.to_f) if override_price
                  end

                  if final_sync_restrictions
                    val_data[:min_stay_arrival] = override&.min_stay.presence || rate&.min_stay || 1
                    val_data[:max_stay_arrival] = override&.max_stay.presence || rate&.max_stay || 999
                    val_data[:closed_to_arrival] = ((override ? override.closed_to_arrival? : rate&.closed_to_arrival?) ? 1 : 0)
                    val_data[:closed_to_departure] = ((override ? override.closed_to_departure? : rate&.closed_to_departure?) ? 1 : 0)
                    val_data[:stop_sell] = ((override ? override.stop_sell? : rate&.stop_sell?) ? 1 : 0)
                  end

                  if current_crp_range.nil?
                    current_crp_range = val_data.merge(date_from: date.to_s, date_to: date.to_s)
                  elsif current_crp_range.except(:date_from, :date_to) == val_data && Date.parse(current_crp_range[:date_to]) + 1.day == date
                    current_crp_range[:date_to] = date.to_s
                  else
                    values << current_crp_range
                    current_crp_range = val_data.merge(date_from: date.to_s, date_to: date.to_s)
                  end
                end

                values << current_crp_range if current_crp_range.present?
              end
            end
          end
        end
      end

      values
    end

    def ensure_property(client)
      mapping = @hotel.channel_mapping || @hotel.create_channel_mapping(provider: provider_name, external_id: "pending")

      payload = {
        property: {
          title: @hotel.name,
          city: @hotel.city || "Unknown City",
          country: "MY", # Channel Manager expects ISO 2-letter country code
          currency: @hotel.default_currency || "MYR",
          timezone: "Asia/Kuala_Lumpur",
          facilities: map_amenities_to_channex_ids(@hotel.amenities, :hotel)
        }
      }

      response = if mapping.external_id == "pending"
                   client.post("/properties", payload)
      else
                   client.put("/properties/#{mapping.external_id}", payload)
      end

      if response["data"] && response["data"]["id"]
        mapping.update!(external_id: response["data"]["id"])
        response["data"]["id"]
      else
        Rails.logger.error "Channel Manager Property Sync Failed: #{response}"
        nil
      end
    end

    def ensure_rate_plans(client, room_type)
      # If room type has no rate plans, find or create a standard one and link it
      if room_type.rate_plans.empty?
        rate_plan = @hotel.rate_plans.find_or_create_by!(name: "Standard Rate") do |rp|
          rp.sell_mode = "per_room"
          rp.currency = @hotel.default_currency || "MYR"
        end
        room_type.room_type_rate_plans.find_or_create_by!(rate_plan: rate_plan)
      end

      room_type.rate_plans.all? do |rate_plan|
        sync_rate_plan(rate_plan, room_type: room_type).present?
      end
    end

    def default_rate_plan_options(rate_plan, room_type: nil)
      room_type ||= rate_plan.room_types.first
      occupancy = room_type&.max_adults.to_i
      occupancy = 1 if occupancy <= 0

      [
        {
          occupancy: occupancy,
          is_primary: true,
          rate: 0
        }
      ]
    end

    def map_amenities_to_channex_ids(amenity_slugs, type)
      return [] if amenity_slugs.blank?

      map = Amenity.lookup_map(type)
      amenity_slugs.map { |slug| map[slug]&.fetch(:channex_id, nil) }.compact
    end

    def success(message)
      OpenStruct.new(success?: true, message: message)
    end

    def failure(message)
      OpenStruct.new(success?: false, message: message)
    end

    def safe_parse_date(value)
      return nil if value.blank?
      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end

    def safe_parse_datetime(value)
      return nil if value.blank?
      DateTime.parse(value.to_s)
    rescue Date::Error, ArgumentError
      nil
    end

    def sync_channel_availability_rules(client, property_id, date_range, room_type_ids)
      overrides = ChannelRoomRate.where(
        room_type_id: room_type_ids,
        rate_plan_id: nil,
        date: date_range
      )

      overrides.group_by { |o| [ o.room_type_id, o.channel_id ] }.each do |(room_type_id, channel_id), chan_overrides|
        room_type = RoomType.find(room_type_id)
        ext_rt_id = mapping_for(room_type).external_id
        next if ext_rt_id == "pending"

        # 1. Clean up existing rules for this room/channel in this range to avoid duplicates
        existing_rules = client.get("/channel_availability_rules", { "filter" => { "property_id" => property_id } }) rescue {}
        if existing_rules["data"].is_a?(Array)
          existing_rules["data"].each do |rule|
            attr = rule["attributes"] || {}
            if attr["title"] == "PMS Override" && attr["affected_channels"]&.include?(channel_id) && attr["affected_room_types"]&.include?(ext_rt_id)
              r_start = Date.parse(attr["start_date"]) rescue nil
              r_end = Date.parse(attr["end_date"]) rescue nil
              if r_start && r_end && (r_start..r_end).overlaps?(date_range)
                client.delete("/channel_availability_rules/#{rule['id']}") rescue nil
              end
            end
          end
        end

        # 2. Push contiguous close_out rules
        close_out_dates = chan_overrides.select(&:stop_sell).map(&:date).sort
        group_dates_into_ranges(close_out_dates).each do |range|
          client.post("/channel_availability_rules", {
            channel_availability_rule: {
              title: "PMS Override",
              type: "close_out",
              affected_channels: [ channel_id ],
              affected_room_types: [ ext_rt_id ],
              days: [ "mo", "tu", "we", "th", "fr", "sa", "su" ],
              start_date: range.first.to_s,
              end_date: range.last.to_s,
              property_id: property_id
            }
          }) rescue nil
        end

        # 3. Push contiguous max_availability rules (allotments)
        max_avail_overrides = chan_overrides.select { |o| o.availability.present? && !o.stop_sell }
        max_avail_overrides.group_by(&:availability).each do |avail_value, overrides_with_val|
          avail_dates = overrides_with_val.map(&:date).sort
          group_dates_into_ranges(avail_dates).each do |range|
            client.post("/channel_availability_rules", {
              channel_availability_rule: {
                title: "PMS Override",
                type: "max_availability",
                value: avail_value.to_i,
                affected_channels: [ channel_id ],
                affected_room_types: [ ext_rt_id ],
                days: [ "mo", "tu", "we", "th", "fr", "sa", "su" ],
                start_date: range.first.to_s,
                end_date: range.last.to_s,
                property_id: property_id
              }
            }) rescue nil
          end
        end
      end
    end

    def group_dates_into_ranges(dates)
      return [] if dates.empty?
      ranges = []
      start_date = dates.first
      prev_date = dates.first

      dates[1..].each do |d|
        if d == prev_date + 1.day
          prev_date = d
        else
          ranges << (start_date..prev_date)
          start_date = d
          prev_date = d
        end
      end
      ranges << (start_date..prev_date)
      ranges
    end

    def create_channel_availability_rule(rule)
      client = Channex::Client.new
      property_id = mapping_for(rule.hotel).external_id

      # Translate PMS room types to Channex room type UUIDs
      ext_rt_ids = rule.affected_room_types.map do |rt_id|
        rt = RoomType.find_by(id: rt_id)
        rt ? mapping_for(rt).external_id : nil
      end.compact.reject { |id| id == "pending" }

      days_array = rule.days.to_s.split(",").map(&:strip).reject(&:blank?)
      days_array = [ "mo", "tu", "we", "th", "fr", "sa", "su" ] if days_array.empty?

      payload = {
        channel_availability_rule: {
          title: rule.title,
          type: rule.rule_type,
          value: rule.value.presence&.to_i,
          affected_channels: rule.affected_channels,
          affected_room_types: ext_rt_ids,
          days: days_array,
          start_date: rule.start_date.to_s,
          end_date: rule.end_date.presence&.to_s,
          property_id: property_id
        }.compact
      }

      response = client.post("/channel_availability_rules", payload)
      if response["data"] && response["data"]["id"]
        # Skip validations/callbacks to prevent infinite loops
        rule.update_columns(external_id: response["data"]["id"])
        true
      else
        Rails.logger.error "Channex: Failed to create availability rule: #{response}"
        false
      end
    end

    def update_channel_availability_rule(rule)
      client = Channex::Client.new
      property_id = mapping_for(rule.hotel).external_id

      ext_rt_ids = rule.affected_room_types.map do |rt_id|
        rt = RoomType.find_by(id: rt_id)
        rt ? mapping_for(rt).external_id : nil
      end.compact.reject { |id| id == "pending" }

      days_array = rule.days.to_s.split(",").map(&:strip).reject(&:blank?)
      days_array = [ "mo", "tu", "we", "th", "fr", "sa", "su" ] if days_array.empty?

      payload = {
        channel_availability_rule: {
          title: rule.title,
          type: rule.rule_type,
          value: rule.value.presence&.to_i,
          affected_channels: rule.affected_channels,
          affected_room_types: ext_rt_ids,
          days: days_array,
          start_date: rule.start_date.to_s,
          end_date: rule.end_date.presence&.to_s,
          property_id: property_id
        }.compact
      }

      response = client.put("/channel_availability_rules/#{rule.external_id}", payload)
      if response["data"] && response["data"]["id"]
        true
      else
        Rails.logger.error "Channex: Failed to update availability rule #{rule.id}: #{response}"
        false
      end
    end

    def delete_channel_availability_rule(external_id)
      client = Channex::Client.new
      client.delete("/channel_availability_rules/#{external_id}")
    end
  end
end
