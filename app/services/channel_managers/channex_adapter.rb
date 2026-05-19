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

    def sync_rate_plan(rate_plan)
      client = Channex::Client.new
      property_id = mapping_for(@hotel).external_id
      room_type_id = mapping_for(rate_plan.room_type).external_id
      mapping = mapping_for(rate_plan)

      payload = {
        rate_plan: {
          property_id: property_id,
          room_type_id: room_type_id,
          title: rate_plan.name,
          currency: rate_plan.currency,
          sell_mode: rate_plan.sell_mode,
          options: default_rate_plan_options(rate_plan)
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
          arrival_date: booking.check_in.to_s,
          departure_date: booking.check_out.to_s,
          amount: format("%.2f", booking.total_amount.to_f),
          currency: booking.currency,
          customer: {
            name: booking.guest_name,
            mail: booking.guest_email,
            phone: booking.guest_phone,
            country: booking.guest_country
          },
          rooms: booking.booking_rooms.map do |br|
            {
              room_type_id: mapping_for(br.room_type).external_id,
              rate_plan_id: mapping_for(br.rate_plan || br.room_type.rate_plans.first).external_id,
              count: br.quantity,
              amount: format("%.2f", br.subtotal.to_f)
            }
          end
        }
      }

      response = client.post("/bookings", payload)

      if response["data"] && response["data"]["id"]
        # Save the external ID to prevent duplicates if we ever fetch it back
        booking.update!(channel_manager_reference: response["data"]["id"], revision_number: response["data"]["revision_id"])
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
        rate_plan = ChannelMapping.find_by(provider: provider_name, external_id: room["rate_plan_id"], mappable_type: "RatePlan")&.mappable

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

          ext_rp_id = mapping_for(rate_plan).external_id
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

            if final_sync_rates && rate&.price
              val_data[:rate] = format("%.2f", rate.price.to_f)
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
      # If room type has no rate plans, create a default one
      if room_type.rate_plans.empty?
        room_type.rate_plans.create!(name: "Standard Rate", sell_mode: "per_room", currency: @hotel.default_currency || "MYR")
      end

      room_type.rate_plans.all? do |rate_plan|
        sync_rate_plan(rate_plan).present?
      end
    end

    def default_rate_plan_options(rate_plan)
      occupancy = rate_plan.room_type.max_adults.to_i
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
  end
end
