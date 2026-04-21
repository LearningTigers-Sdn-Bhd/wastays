require "ostruct"

module ChannelManagers
  class ChannexAdapter < BaseAdapter
    def onboard_hotel
      client = Channex::Client.new

      # 1. Create Property
      property_id = ensure_property(client)
      return failure("Failed to create Channex property") unless property_id

      # 2. Create Room Types
      @hotel.room_types.each do |room_type|
        ensure_room_type(client, room_type, property_id)
      end

      # 3. Create Rate Plans (for each room type)
      @hotel.room_types.each do |room_type|
        ensure_rate_plans(client, room_type)
      end

      success("Hotel onboarded to Channex")
    end

    def push_ari(date_range:)
      client = Channex::Client.new
      property_id = mapping_for(@hotel).external_id

      # 1. Push Availability (Room Type level)
      push_availability(client, property_id, date_range)

      # 2. Push Restrictions/Rates (Rate Plan level)
      push_restrictions(client, property_id, date_range)

      success("ARI pushed to Channex")
    end

    def ingest_booking(payload:)
      # payload is the raw JSON from Channex booking revision feed or GET /booking_revisions/:id
      data = payload["data"] || payload

      # Map Channex status to WAStays status
      # Channex statuses: new, modified, cancelled
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
          # Channex doesn't always provide gender/doc_type, but we'll take what we can
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
      values = []
      @hotel.room_types.each do |room_type|
        ext_rt_id = mapping_for(room_type).external_id
        next if ext_rt_id == "pending"

        room_type.room_inventories.where(date: date_range).each do |inventory|
          values << {
            property_id: property_id,
            room_type_id: ext_rt_id,
            date: inventory.date.to_s,
            availability: inventory.quantity
          }
        end
      end

      client.post("/availability", { values: values }) if values.any?
    end

    def push_restrictions(client, property_id, date_range)
      values = []
      @hotel.room_types.each do |room_type|
        room_type.rate_plans.each do |rate_plan|
          ext_rp_id = mapping_for(rate_plan).external_id
          next if ext_rp_id == "pending"

          rate_plan.room_rates.where(date: date_range).each do |rate|
            values << {
              property_id: property_id,
              rate_plan_id: ext_rp_id,
              date: rate.date.to_s,
              rate: rate.price.to_f,
              currency: rate.currency
            }
          end
        end
      end

      client.post("/restrictions", { values: values }) if values.any?
    end

    def ensure_property(client)
      mapping = @hotel.channel_mapping || @hotel.create_channel_mapping(provider: provider_name, external_id: "pending")
      return mapping.external_id if mapping.external_id != "pending"

      payload = {
        property: {
          name: @hotel.name,
          city: @hotel.city,
          country: "MY", # Channex expects ISO 2-letter country code
          currency: @hotel.default_currency || "MYR",
          timezone: "Kuala Lumpur" # Default for now
        }
      }

      response = client.post("/properties", payload)
      if response["data"] && response["data"]["id"]
        mapping.update!(external_id: response["data"]["id"])
        response["data"]["id"]
      else
        nil
      end
    end

    def ensure_room_type(client, room_type, property_id)
      mapping = room_type.channel_mapping || room_type.create_channel_mapping(provider: provider_name, external_id: "pending")
      return mapping.external_id if mapping.external_id != "pending"

      payload = {
        room_type: {
          property_id: property_id,
          title: room_type.name,
          count_of_rooms: room_type.quantity,
          occ_adults: room_type.max_adults,
          occ_children: room_type.max_children || 0,
          occ_infants: 0,
          default_occupancy: room_type.max_adults
        }
      }

      response = client.post("/room_types", payload)
      if response["data"] && response["data"]["id"]
        mapping.update!(external_id: response["data"]["id"])
        response["data"]["id"]
      else
        nil
      end
    end

    def ensure_rate_plans(client, room_type)
      # If room type has no rate plans, create a default one
      if room_type.rate_plans.empty?
        room_type.rate_plans.create!(name: "Standard Rate", sell_mode: "per_room", currency: @hotel.default_currency || "MYR")
      end

      room_type.rate_plans.each do |rate_plan|
        ensure_rate_plan(client, rate_plan, room_type.channel_mapping.external_id)
      end
    end

    def ensure_rate_plan(client, rate_plan, room_type_id)
      mapping = rate_plan.channel_mapping || rate_plan.create_channel_mapping(provider: provider_name, external_id: "pending")
      return mapping.external_id if mapping.external_id != "pending"

      payload = {
        rate_plan: {
          room_type_id: room_type_id,
          title: rate_plan.name,
          currency: rate_plan.currency,
          sell_mode: rate_plan.sell_mode
        }
      }

      response = client.post("/rate_plans", payload)
      if response["data"] && response["data"]["id"]
        mapping.update!(external_id: response["data"]["id"])
        response["data"]["id"]
      else
        nil
      end
    end

    def success(message)
      OpenStruct.new(success?: true, message: message)
    end

    def failure(message)
      OpenStruct.new(success?: false, message: message)
    end
  end
end
