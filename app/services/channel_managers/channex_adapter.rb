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

    def push_ari(date_range:)
      client = Channex::Client.new
      property_id = mapping_for(@hotel).external_id

      # 1. Push Availability (Room Type level)
      availability_result = push_availability(client, property_id, date_range)
      return failure(availability_result[:message]) unless availability_result[:ok]

      # 2. Push Restrictions/Rates (Rate Plan level)
      restrictions_result = push_restrictions(client, property_id, date_range)
      return failure(restrictions_result[:message]) unless restrictions_result[:ok]

      success("ARI pushed to Channel Manager")
    end

    def ingest_booking(payload:)
      data = payload["data"] || payload

      wa_status = case data["status"]
      when "cancelled" then "cancelled"
      else "confirmed"
      end

      {
        hotel: @hotel,
        external_reference: data["ota_reservation_id"] || data["id"],
        channel_manager_reference: data["id"],
        revision_number: data["revision_id"] || 0,
        status: wa_status,
        check_in: Date.parse(data["arrival_date"]),
        check_out: Date.parse(data["departure_date"]),
        guest_details: {
          name: data.dig("customer", "name"),
          email: data.dig("customer", "email"),
          phone: data.dig("customer", "phone"),
          country: data.dig("customer", "country")
        },
        rooms: parse_booking_rooms(data["rooms"] || []),
        total_amount: data["amount"].to_f,
        currency: data["currency"] || "MYR",
        source: data["ota_name"] || "channex"
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
          quantity: room["count"] || 1,
          amount: room["amount"].to_f
        }
      end.compact
    end

    def provider_name
      "channex"
    end

    def push_availability(client, property_id, date_range)
      values = push_availability_values(date_range)
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

    def push_restrictions(client, property_id, date_range)
      values = push_restrictions_values(date_range)
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

    def push_availability_values(date_range)
      values = []
      property_id = mapping_for(@hotel).external_id
      
      @hotel.room_types.each do |room_type|
        ext_rt_id = mapping_for(room_type).external_id
        next if ext_rt_id == "pending"

        current_range = nil

        room_type.room_inventories.where(date: date_range).order(:date).each do |inventory|
          val_data = {
            property_id: property_id,
            room_type_id: ext_rt_id,
            availability: inventory.quantity
          }

          if current_range.nil?
            current_range = val_data.merge(date_from: inventory.date.to_s, date_to: inventory.date.to_s)
          elsif current_range.except(:date_from, :date_to) == val_data && Date.parse(current_range[:date_to]) + 1.day == inventory.date
            current_range[:date_to] = inventory.date.to_s
          else
            values << current_range
            current_range = val_data.merge(date_from: inventory.date.to_s, date_to: inventory.date.to_s)
          end
        end
        
        values << current_range if current_range.present?
      end
      values
    end

    def push_restrictions_values(date_range)
      values = []
      property_id = mapping_for(@hotel).external_id
      
      @hotel.room_types.each do |room_type|
        occupancy = room_type.max_adults.to_i
        occupancy = 1 if occupancy <= 0

        room_type.rate_plans.each do |rate_plan|
          ext_rp_id = mapping_for(rate_plan).external_id
          next if ext_rp_id == "pending"

          current_range = nil

          # Only push rates that match the rate plan's currency to avoid conflicting payloads
          rate_plan.room_rates.where(date: date_range, currency: rate_plan.currency).order(:date).each do |rate|
            val_data = {
              property_id: property_id,
              rate_plan_id: ext_rp_id,
              rate: format("%.2f", rate.price.to_f),
              currency: rate.currency,
              occupancy: occupancy
            }

            val_data[:min_stay_arrival] = rate.min_stay if rate.min_stay.present?
            val_data[:max_stay_arrival] = rate.max_stay if rate.max_stay.present?
            val_data[:closed_to_arrival] = rate.closed_to_arrival ? 1 : 0 if !rate.closed_to_arrival.nil?
            val_data[:closed_to_departure] = rate.closed_to_departure ? 1 : 0 if !rate.closed_to_departure.nil?
            val_data[:stop_sell] = rate.stop_sell ? 1 : 0 if !rate.stop_sell.nil?

            if current_range.nil?
              current_range = val_data.merge(date_from: rate.date.to_s, date_to: rate.date.to_s)
            elsif current_range.except(:date_from, :date_to) == val_data && Date.parse(current_range[:date_to]) + 1.day == rate.date
              current_range[:date_to] = rate.date.to_s
            else
              values << current_range
              current_range = val_data.merge(date_from: rate.date.to_s, date_to: rate.date.to_s)
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
  end
end
