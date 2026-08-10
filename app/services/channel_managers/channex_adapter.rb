# frozen_string_literal: true

module ChannelManagers
  class ChannexAdapter < BaseAdapter
    SETTLEMENT_SOURCE_ALIASES = {
      "bookingcom" => "booking_com",
      "booking_dot_com" => "booking_com",
      "agoda_com" => "agoda",
      "expediacom" => "expedia",
      "traveloka_com" => "traveloka"
    }.freeze
    COLLECTION_BY_MAP = {
      "property" => "property",
      "hotel" => "property",
      "guest" => "property",
      "direct" => "property",
      "ota" => "ota",
      "channel" => "ota",
      "agency" => "ota",
      "online_travel_agency" => "ota"
    }.freeze
    SETTLEMENT_METHOD_MAP = {
      "credit_card" => "guest_card",
      "creditcard" => "guest_card",
      "card" => "guest_card",
      "debit_card" => "guest_card",
      "guest_card" => "guest_card",
      "bank_transfer" => "bank_transfer",
      "banktransfer" => "bank_transfer",
      "wire_transfer" => "bank_transfer",
      "wire" => "bank_transfer",
      "virtual_card" => "virtual_card",
      "virtualcard" => "virtual_card",
      "virtual_credit_card" => "virtual_card",
      "vcc" => "virtual_card",
      "virtual" => "virtual_card",
      "bank" => "bank_transfer"
    }.freeze
    def onboard_hotel
      @room_types_for_sync = nil
      client = Channex::Client.new

      # 1. Create Property
      property_id = ensure_property(client)
      return failure("Failed to create Channel Manager property. Check logs for details.") unless property_id

      # 2. Create Room Types
      @hotel.room_types.each do |room_type|
        rt_id = sync_room_type(room_type)
        return failure("Failed to create Channel Manager room type: #{room_type.name}") unless rt_id
      end

      # 3. Create each compatible Rate Plan for each Room Type. Unsupported
      # assignments do not leave onboarding half-finished; they are reported as
      # a partial result and remain available to direct booking.
      skipped = []
      @hotel.room_types.each do |room_type|
        result = ensure_rate_plans(client, room_type)
        return failure("Failed to create Channel Manager rate plans for: #{room_type.name}") unless result[:ok]

        skipped.concat(result[:skipped])
      end

      retirement = retire_unsupported_mappings(
        client,
        property_id,
        Date.current..(Date.current + 499.days)
      )
      unless retirement[:ok]
        return failure(retirement[:message], warnings: retirement[:warnings], task_ids: { restrictions: retirement[:task_id] })
      end

      if skipped.any?
        partial_success(
          "Hotel onboarded; #{skipped.size} rate plan assignment(s) were not distributed.",
          warnings: skipped,
          task_ids: { restrictions: retirement[:task_id] }
        )
      else
        success("Hotel onboarded to Channel Manager")
      end
    rescue Channex::Client::RetryableRequestError
      raise
    rescue StandardError => e
      failure("Onboarding error: #{e.message}")
    end

    def sync_hotel
      client = Channex::Client.new
      ensure_property(client)
    end

    def connected_channels(force_refresh: false)
      client = Channex::Client.new
      property_mapping = mapping_for(@hotel)
      return [] if property_mapping.nil? || property_mapping.external_id.to_s.start_with?("pending")

      property_id = property_mapping.external_id

      cache_key = "channex:channels:#{@hotel.id}"
      Rails.cache.delete(cache_key) if force_refresh

      Rails.cache.fetch(cache_key, expires_in: 10.minutes) do
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

      response = if mapping.external_id.to_s.start_with?("pending")
                   client.post("/room_types", payload)
      else
                   client.put("/room_types/#{mapping.external_id}", payload)
      end
      raise_if_retryable_response!(response, "Room type sync")

      if response_warnings(response).empty? && response["data"] && response["data"]["id"]
        mapping.update!(external_id: response["data"]["id"])
        response["data"]["id"]
      else
        Rails.logger.error "Channel Manager Room Type Sync Failed (#{room_type.name}): #{response}"
        nil
      end
    end

    def sync_rate_plan(rate_plan, room_type: nil)
      room_type ||= rate_plan.room_types.first
      return nil if room_type.blank?
      capability = rate_plan.channex_capability(room_type: room_type)
      return nil unless capability.supported?

      client = Channex::Client.new
      property_id = mapping_for(@hotel).external_id

      room_type_id = mapping_for(room_type).external_id
      room_type_rate_plan = room_type.room_type_rate_plans.find_by(rate_plan: rate_plan)
      return nil if room_type_rate_plan.blank?
      mapping = mapping_for(room_type_rate_plan)

      options = default_rate_plan_options(rate_plan, room_type: room_type)
      if options.nil?
        Rails.logger.error "Channel Manager Rate Plan Sync Skipped (#{rate_plan.name} / #{room_type.name}): occupancy ladder could not be resolved"
        return nil
      end

      payload = {
        rate_plan: {
          property_id: property_id,
          room_type_id: room_type_id,
          title: "#{rate_plan.name} (#{room_type.name})",
          currency: rate_plan.currency,
          sell_mode: rate_plan.sell_mode,
          rate_mode: "manual",
          options: options
        }
      }
      if capability.flattened?
        payload[:rate_plan][:children_fee] = format_money(rate_plan.channex_children_fee)
        payload[:rate_plan][:infant_fee] = format_money(rate_plan.channex_infant_fee)
      end

      response = if mapping.external_id.to_s.start_with?("pending")
                   client.post("/rate_plans", payload)
      else
                   client.put("/rate_plans/#{mapping.external_id}", payload)
      end
      raise_if_retryable_response!(response, "Rate plan sync")

      if response_warnings(response).empty? && response["data"] && response["data"]["id"]
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

    def create_channel_availability_rule(rule)
      client = Channex::Client.new
      property_id = mapping_for(rule.hotel).external_id

      # Translate PMS room types to Channex room type UUIDs
      ext_rt_ids = rule.affected_room_types.map do |rt_id|
        rt = RoomType.find_by(id: rt_id)
        rt ? mapping_for(rt).external_id : nil
      end.compact.reject { |id| id.to_s.start_with?("pending") }

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
      end.compact.reject { |id| id.to_s.start_with?("pending") }

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

    def push_ari(date_range:, sync_availability: true, sync_rates: true, sync_restrictions: true, room_type_ids: nil, rate_plan_ids: nil, rate_plan_fields: nil)
      @room_types_for_sync = nil
      @room_rates_for_resolution = {}
      @derived_settings_by_channel_id = nil
      client = Channex::Client.new
      property_id = mapping_for(@hotel).external_id
      task_ids = {}

      if sync_availability
        availability_result = push_availability(client, property_id, date_range, room_type_ids: room_type_ids)
        unless availability_result[:ok]
          return record_sync_result(failure(availability_result[:message], warnings: availability_result[:warnings], task_ids: task_ids))
        end

        task_ids[:availability] = availability_result[:task_id]
      end

      skipped = []
      restrictions_sent = false
      if sync_rates || sync_restrictions
        restrictions_result = push_restrictions(client, property_id, date_range, rate_plan_ids: rate_plan_ids, sync_rates: sync_rates, sync_restrictions: sync_restrictions, rate_plan_fields: rate_plan_fields)
        skipped = restrictions_result[:skipped]
        unless restrictions_result[:ok]
          return record_sync_result(failure(restrictions_result[:message], warnings: restrictions_result[:warnings], task_ids: task_ids))
        end

        restrictions_sent = restrictions_result[:sent]
        task_ids[:restrictions] = restrictions_result[:task_id]
      end

      result = if skipped.any? && restrictions_sent
        partial_success("ARI pushed with #{skipped.size} unsupported rate plan assignment(s).", warnings: skipped, task_ids: task_ids)
      elsif skipped.any? && sync_availability
        availability_only("Availability pushed; pricing is unsupported for #{skipped.size} rate plan assignment(s).", warnings: skipped, task_ids: task_ids)
      elsif skipped.any?
        unsupported_pricing("No pricing was pushed because the selected rate plan assignments are unsupported.", warnings: skipped)
      else
        success("ARI pushed to Channel Manager", task_ids: task_ids)
      end

      record_sync_result(result)
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
            rp = br.rate_plan || br.room_type.standard_rate_plan
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

      payload = payload.to_h.with_indifferent_access
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

      # Keep the provider identity separate from Booking#revision_number. A
      # Channex revision can be a UUID, and replacing it with a timestamp would
      # make settlement idempotency and audit trails impossible.
      revision_id = fetch_attribute(attributes, raw_data, "revision_id").presence ||
        fetch_attribute(attributes, raw_data, "id").presence
      external_reference = attributes["ota_reservation_id"].presence || attributes["unique_id"].presence || attributes["id"].presence
      channel_manager_reference = attributes["booking_id"].presence || attributes["id"].presence

      {
        hotel: @hotel,
        external_reference: external_reference,
        channel_manager_reference: channel_manager_reference,
        revision_number: numeric_revision_for(revision_id, attributes["inserted_at"]),
        revision_id: revision_id,
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
        source: attributes["ota_name"] || "channex",
        settlement: settlement_for(
          attributes: attributes,
          channel_manager_reference: channel_manager_reference,
          external_reference: external_reference,
          revision_id: revision_id
        )
      }
    end

    private

    def settlement_for(attributes:, channel_manager_reference:, external_reference:, revision_id:)
      source_value = first_present(attributes["ota_name"], attributes["source"])
      source = booking_source_for(source_value)
      source_resolution = source_resolution_for(source, source_value)
      currency = valid_currency(attributes["currency"])
      gross_amount = decimal_amount(attributes["amount"])
      commission_amount = [ decimal_amount(
        first_present(attributes["commission_amount"], attributes["commission"], attributes.dig("fees", "commission"))
      ), gross_amount ].min
      virtual_card = virtual_card_metadata(
        attributes: attributes,
        currency: currency,
        settlement_method: settlement_method_for(attributes)
      )
      collection_by = collection_by_for(attributes)
      settlement_method = settlement_method_for(attributes)

      {
        provider: provider_name,
        booking_source_key: source&.key,
        channel_manager_reference: channel_manager_reference,
        external_reference: external_reference,
        revision_id: revision_id,
        collection_by: collection_by,
        settlement_method: settlement_method,
        currency: currency,
        gross_amount: gross_amount,
        commission_amount: commission_amount,
        expected_net_amount: gross_amount - commission_amount,
        status: settlement_status(
          attributes: attributes,
          source_resolution: source_resolution,
          collection_by: collection_by,
          settlement_method: settlement_method,
          virtual_card: virtual_card
        ),
        virtual_card: virtual_card,
        metadata: safe_settlement_metadata(
          attributes: attributes,
          source_resolution: source_resolution,
          collection_by: collection_by,
          settlement_method: settlement_method
        )
      }
    end

    def booking_source_for(source_value)
      return nil if source_value.blank?

      normalized = BookingSource.normalize(source_value)
      canonical_key = SETTLEMENT_SOURCE_ALIASES.fetch(normalized, normalized)
      BookingSource.find_by(key: canonical_key) || BookingSource.find_by_source(source_value)
    end

    def source_resolution_for(source, source_value)
      return "unknown" if source_value.blank? || source.blank?
      return "inactive" unless source.active?
      return "non_ota" unless source.kind == "ota"

      "resolved"
    end

    def collection_by_for(attributes)
      value = normalized_token(
        first_present(
          attributes["payment_collect"],
          attributes.dig("payment", "collect"),
          attributes.dig("payment", "payment_collect")
        )
      )
      COLLECTION_BY_MAP.fetch(value, "unknown")
    end

    def settlement_method_for(attributes)
      payment_type = normalized_token(
        first_present(
          attributes["payment_type"],
          attributes.dig("payment", "type"),
          attributes.dig("payment", "payment_type")
        )
      )
      guarantee = attributes["guarantee"].presence || attributes.dig("payment", "guarantee")
      guarantee = guarantee.is_a?(Hash) ? guarantee : {}
      virtual_card = truthy?(first_value(guarantee, "is_virtual", "virtual", "is_virtual_card")) ||
        normalized_token(guarantee["card_type"]).in?(%w[virtual virtual_card virtual_credit_card vcc])
      return "virtual_card" if virtual_card

      SETTLEMENT_METHOD_MAP.fetch(payment_type, "unknown")
    end

    def settlement_status(attributes:, source_resolution:, collection_by:, settlement_method:, virtual_card:)
      return "needs_attention" unless source_resolution == "resolved"
      return "cancelled" if normalized_token(attributes["status"]) == "cancelled"
      return "property_collection_required" if collection_by == "property"
      return "needs_attention" if collection_by == "unknown" || settlement_method == "unknown"
      return "awaiting_ota_settlement" unless settlement_method == "virtual_card"

      effective_date = virtual_card[:effective_date]
      return "virtual_card_not_ready" if effective_date.present? && effective_date > Date.current

      "ready_to_charge"
    end

    # Only the fields required to decide how a virtual card may be handled are
    # copied. In particular, never copy the provider's guarantee object: it can
    # contain PANs, CVVs, card numbers, tokens, or opaque authorization data.
    def virtual_card_metadata(attributes:, currency:, settlement_method:)
      guarantee = attributes["guarantee"].presence || attributes.dig("payment", "guarantee")
      guarantee = guarantee.is_a?(Hash) ? guarantee : {}
      guarantee_card = guarantee["card"].is_a?(Hash) ? guarantee["card"] : {}
      virtual_card = attributes["virtual_card"].is_a?(Hash) ? attributes["virtual_card"] : {}
      values = guarantee.merge(guarantee_card).merge(virtual_card)
      return {} if values.empty? && settlement_method != "virtual_card"

      is_virtual_value = first_value(values, "is_virtual", "virtual", "is_virtual_card")
      is_virtual = if is_virtual_value.nil?
        settlement_method == "virtual_card" ? true : nil
      else
        truthy?(is_virtual_value)
      end

      {
        is_virtual: is_virtual,
        currency: valid_currency(values["currency"] || values["card_currency"] || currency),
        available_balance: decimal_or_nil(
          values["available_balance"] || values["available_amount"] || values["balance"]
        ),
        effective_date: safe_parse_date(
          values["effective_date"] || values["card_effective_date"] || values["activation_date"]
        ),
        expiration_date: safe_parse_date(
          values["expiration_date"] || values["card_expiration_date"] || values["expiry_date"]
        )
      }.compact
    end

    def safe_settlement_metadata(attributes:, source_resolution:, collection_by:, settlement_method:)
      {
        "ota_name" => attributes["ota_name"].to_s.strip.presence,
        "provider_status" => normalized_token(attributes["status"]).presence,
        "payment_collect" => normalized_token(
          first_present(
            attributes["payment_collect"],
            attributes.dig("payment", "collect"),
            attributes.dig("payment", "payment_collect")
          )
        ).presence,
        "payment_type" => normalized_token(
          first_present(
            attributes["payment_type"],
            attributes.dig("payment", "type"),
            attributes.dig("payment", "payment_type")
          )
        ).presence,
        "source_resolution" => source_resolution,
        "collection_by" => collection_by,
        "settlement_method" => settlement_method
      }.compact
    end

    def first_present(*values)
      values.find(&:present?)
    end

    def first_value(hash, *keys)
      keys.each do |key|
        return hash[key] if hash.key?(key)
        return hash[key.to_sym] if hash.key?(key.to_sym)
      end

      nil
    end

    def fetch_attribute(attributes, raw_data, key)
      attributes[key] || attributes[key.to_sym] || raw_data[key] || raw_data[key.to_sym]
    end

    def numeric_revision_for(revision_id, inserted_at)
      return revision_id.to_i if revision_id.to_s.match?(/\A\d+\z/)

      safe_parse_datetime(inserted_at)&.to_i || 0
    end

    def normalized_token(value)
      value.to_s.downcase.strip.gsub(/[-\s]+/, "_")
    end

    def truthy?(value)
      value == true || value.to_s.downcase.in?(%w[true 1 yes y])
    end

    def decimal_amount(value)
      value = value["amount"] || value[:amount] if value.is_a?(Hash)
      BigDecimal(value.to_s)
    rescue ArgumentError, TypeError
      BigDecimal("0")
    end

    def decimal_or_nil(value)
      return nil if value.blank?

      decimal_amount(value)
    end

    def valid_currency(value)
      normalized = CurrencyCatalog.normalize(value, fallback: @hotel.default_currency || "MYR")
      CurrencyCatalog.valid?(normalized) ? normalized : (@hotel.default_currency || "MYR")
    end

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

      return { ok: true, warnings: [] } if values.empty?

      response = client.post("/availability", { values: values })

      if response[:error] || response["error"]
        if response[:retryable] || response["retryable"]
          raise Channex::Client::RetryableRequestError, "Availability sync retryable failure: #{response[:details] || response['details'] || response}"
        end
        return { ok: false, message: "Availability sync failed: #{response[:details] || response['details'] || response}", warnings: [] }
      end

      warnings = response.dig("meta", "warnings").to_a
      if warnings.any?
        return { ok: false, message: "Availability sync rejected one or more values", warnings: warnings }
      end

      # For Stage 2 Certification: Task IDs are in response["data"][0]["id"] (Array)
      # or response["data"]["id"] (Hash)
      data = response["data"]
      task_id = data.is_a?(Array) ? data.dig(0, "id") : data&.fetch("id", nil)

      Rails.logger.info "Channex Availability Task ID: #{task_id}" if task_id

      { ok: true, task_id: task_id, warnings: [] }
    end

    def push_restrictions(client, property_id, date_range, rate_plan_ids: nil, sync_rates: true, sync_restrictions: true, rate_plan_fields: nil)
      build = push_restrictions_values(date_range, rate_plan_ids: rate_plan_ids, sync_rates: sync_rates, sync_restrictions: sync_restrictions, rate_plan_fields: rate_plan_fields)
      values = build[:values]
      skipped = build[:skipped]
      return { ok: true, sent: false, skipped: skipped, warnings: [] } if values.empty?

      response = client.post("/restrictions", { values: values })

      if response[:error] || response["error"]
        if response[:retryable] || response["retryable"]
          raise Channex::Client::RetryableRequestError, "Restrictions sync retryable failure: #{response[:details] || response['details'] || response}"
        end
        return { ok: false, message: "Restrictions sync failed: #{response[:details] || response['details'] || response}", skipped: skipped, warnings: [] }
      end

      warnings = response.dig("meta", "warnings").to_a
      if warnings.any?
        return { ok: false, message: "Restrictions sync rejected one or more values", skipped: skipped, warnings: warnings }
      end

      # For Stage 2 Certification: Task IDs are in response["data"][0]["id"]
      data = response["data"]
      task_id = data.is_a?(Array) ? data.dig(0, "id") : data&.fetch("id", nil)

      Rails.logger.info "Channex Restrictions Task ID: #{task_id}" if task_id

      { ok: true, sent: true, skipped: skipped, task_id: task_id, warnings: [] }
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
        next if ext_rt_id.to_s.start_with?("pending")

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
      skipped = []
      property_id = mapping_for(@hotel).external_id

      room_types_for_sync.each do |room_type|
        room_type.room_type_rate_plans.each do |room_type_rate_plan|
          rate_plan = room_type_rate_plan.rate_plan
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

          capability = rate_plan.channex_capability(room_type: room_type)
          unless capability.supported?
            mapping = room_type_rate_plan.channel_mapping
            # Walk-in and corporate plans are intentionally internal. They are
            # not a partial channel failure unless an old live mapping exists
            # and must be retired.
            if !rate_plan.kind.in?(RatePlan::DISTRIBUTABLE_KINDS) && !live_mapping?(mapping)
              next
            end
            if sync_restrictions && live_mapping?(mapping)
              values << retirement_value(
                property_id: property_id,
                external_rate_plan_id: mapping.external_id,
                date_range: effective_range
              )
              reason = "#{capability.reason}. Stop-sold in Channex; manual removal remains outstanding"
            else
              reason = capability.reason
            end
            skipped << skipped_plan(rate_plan, room_type, reason)
            next
          end

          ext_rp_id = mapping_for(room_type_rate_plan).external_id
          next if ext_rp_id.to_s.start_with?("pending")

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
          rates = room_rates_for_resolution(room_type, effective_range, rate_plan.currency)
          rates_by_date = rates.select { |item| item.rate_plan_id == rate_plan.id }.index_by(&:date)
          resolved_rates_by_date = {}

          if final_sync_rates
            effective_range.each do |date|
              rate = rates_by_date[date]
              is_full_restrictions_sync = sync_restrictions && specific_fields.nil?
              is_full_rates_sync = sync_rates && specific_fields.nil?
              next if rate.nil? && !is_full_restrictions_sync && !is_full_rates_sync

              resolved_rates_by_date[date] = resolved_channex_rate(
                rate_plan: rate_plan,
                room_type: room_type,
                room_type_rate_plan: room_type_rate_plan,
                date: date,
                rates: rates
              )
            end

            unresolved_date = resolved_rates_by_date.key(nil)
            if unresolved_date
              skipped << skipped_plan(rate_plan, room_type, "Could not resolve every required occupancy for #{unresolved_date}")
              next
            end
          end

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
              val_data[:rate] = resolved_rates_by_date.fetch(date)
            end

            if final_sync_restrictions
              # Map supported restrictions surgically
              if specific_fields
                s_fields = specific_fields.map(&:to_s)
                val_data[:min_stay_arrival] = rate.min_stay if s_fields.include?("min_stay") && rate.min_stay.present?
                val_data[:max_stay] = rate.max_stay if s_fields.include?("max_stay") && rate.max_stay.present?
                val_data[:closed_to_arrival] = rate.closed_to_arrival ? 1 : 0 if s_fields.include?("closed_to_arrival") && !rate.closed_to_arrival.nil?
                val_data[:closed_to_departure] = rate.closed_to_departure ? 1 : 0 if s_fields.include?("closed_to_departure") && !rate.closed_to_departure.nil?
                val_data[:stop_sell] = rate.stop_sell ? 1 : 0 if s_fields.include?("stop_sell") && !rate.stop_sell.nil?
              else
                # For Full Sync, we provide a full snapshot with defaults for each date and rate plan.
                # This ensures that any stale values in the channel manager are overwritten.
                val_data[:min_stay_arrival] = rate&.min_stay || 1
                val_data[:max_stay] = rate&.max_stay || 0
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
          if ext_rp_id.present? && !ext_rp_id.to_s.start_with?("pending")
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
                    base_rate = resolved_rates_by_date[date]
                    val_data[:rate] = channel_rate_value(
                      base_rate,
                      override: override,
                      derived_setting: derived_setting_for(channel["id"]),
                      per_person: rate_plan.sell_mode == "per_person"
                    ) if base_rate
                  end

                  if final_sync_restrictions
                    val_data[:min_stay_arrival] = override&.min_stay.presence || rate&.min_stay || 1
                    val_data[:max_stay] = override&.max_stay.presence || rate&.max_stay || 0
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

      { values: values, skipped: skipped.uniq }
    end

    def room_types_for_sync
      @room_types_for_sync ||= @hotel.room_types.includes(
        :channel_mapping,
        room_type_rate_plans: [ :channel_mapping, :occupancy_prices, { rate_plan: :rate_plan_age_bands } ]
      ).to_a
    end

    def room_rates_for_resolution(room_type, date_range, currency)
      @room_rates_for_resolution ||= {}
      key = [ room_type.id, date_range.first, date_range.last, currency ]
      @room_rates_for_resolution[key] ||= room_type.room_rates
        .where(date: date_range, currency: currency)
        .to_a
    end

    def resolved_channex_rate(rate_plan:, room_type:, room_type_rate_plan:, date:, rates:)
      if rate_plan.sell_mode == "per_person"
        (1..[ room_type.max_adults.to_i, 1 ].max).map do |occupancy|
          result = Rates::ResolveEffectiveNightlyPrice.call(
            room_type: room_type,
            rate_plan: rate_plan,
            date: date,
            currency: rate_plan.currency,
            adults: occupancy,
            children: 0,
            room_rates: rates,
            room_type_rate_plan: room_type_rate_plan
          )
          return nil if result.amount.nil?

          [ occupancy, format_money(result.amount) ]
        end
      else
        occupancy = rate_plan.base_occupancy.to_i.clamp(1, [ room_type.max_adults.to_i, 1 ].max)
        result = Rates::ResolveEffectiveNightlyPrice.call(
          room_type: room_type,
          rate_plan: rate_plan,
          date: date,
          currency: rate_plan.currency,
          adults: occupancy,
          children: 0,
          room_rates: rates,
          room_type_rate_plan: room_type_rate_plan
        )
        result.amount.nil? ? nil : format_money(result.amount)
      end
    end

    def channel_rate_value(base_rate, override:, derived_setting:, per_person:)
      if per_person
        base_rate.map { |occupancy, amount| [ occupancy, format_money(adjust_channel_rate(amount.to_d, derived_setting)) ] }
      else
        amount = override&.price.presence || adjust_channel_rate(base_rate.to_d, derived_setting)
        format_money(amount)
      end
    end

    # Looked up once per push: the setting is constant for a channel, and the
    # caller sits inside a per-date loop that can span 500 nights.
    def derived_setting_for(channel_id)
      @derived_settings_by_channel_id ||= @hotel.channel_derived_settings.index_by(&:channel_id)
      @derived_settings_by_channel_id[channel_id]
    end

    def adjust_channel_rate(amount, derived_setting)
      return amount unless derived_setting

      case derived_setting.pricing_mode
      when "multiplier" then amount * (1 + derived_setting.pricing_value.to_d / 100)
      when "offset" then amount + derived_setting.pricing_value.to_d
      else amount
      end
    end

    def skipped_plan(rate_plan, room_type, reason)
      {
        rate_plan_id: rate_plan.id,
        rate_plan_name: rate_plan.name,
        room_type_id: room_type.id,
        room_type_name: room_type.name,
        reason: reason
      }
    end

    def retire_unsupported_mappings(client, property_id, date_range)
      values = room_types_for_sync.flat_map do |room_type|
        room_type.room_type_rate_plans.filter_map do |assignment|
          capability = assignment.rate_plan.channex_capability(room_type: room_type)
          next if capability.supported? || !live_mapping?(assignment.channel_mapping)

          retirement_value(
            property_id: property_id,
            external_rate_plan_id: assignment.channel_mapping.external_id,
            date_range: date_range
          )
        end
      end
      return { ok: true, warnings: [] } if values.empty?

      response = client.post("/restrictions", { values: values })
      if response[:error] || response["error"]
        if response[:retryable] || response["retryable"]
          raise Channex::Client::RetryableRequestError, "Rate plan retirement retryable failure: #{response[:details] || response['details'] || response}"
        end
        return { ok: false, message: "Rate plan retirement failed: #{response[:details] || response['details'] || response}", warnings: [] }
      end

      warnings = response.dig("meta", "warnings").to_a
      return { ok: false, message: "Rate plan retirement rejected one or more values", warnings: warnings } if warnings.any?

      data = response["data"]
      task_id = data.is_a?(Array) ? data.dig(0, "id") : data&.fetch("id", nil)
      { ok: true, warnings: [], task_id: task_id }
    end

    def retirement_value(property_id:, external_rate_plan_id:, date_range:)
      {
        property_id: property_id,
        rate_plan_id: external_rate_plan_id,
        date_from: date_range.first.to_s,
        date_to: date_range.last.to_s,
        stop_sell: 1
      }
    end

    def live_mapping?(mapping)
      mapping.present? && !mapping.external_id.to_s.start_with?("pending")
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

      response = if mapping.external_id.to_s.start_with?("pending")
                   client.post("/properties", payload)
      else
                   client.put("/properties/#{mapping.external_id}", payload)
      end
      raise_if_retryable_response!(response, "Property sync")

      if response_warnings(response).empty? && response["data"] && response["data"]["id"]
        mapping.update!(external_id: response["data"]["id"])
        response["data"]["id"]
      else
        Rails.logger.error "Channel Manager Property Sync Failed: #{response}"
        nil
      end
    end

    def ensure_rate_plans(client, room_type)
      # If room type has no rate plans, create a standard one of its own. The
      # lookup must stay scoped to the room type: every room type carries its
      # own "Standard Rate" plan, so searching hotel-wide would return another
      # room type's plan and link the two together, making a rate edit on one
      # bleed into the other.
      if room_type.rate_plans.empty?
        rate_plan = @hotel.rate_plans.create!(
          name: "Standard Rate",
          kind: "standard",
          currency: @hotel.default_currency || "MYR"
        )
        room_type.room_type_rate_plans.create!(rate_plan: rate_plan)
      end

      skipped = []
      ok = room_type.rate_plans.all? do |rate_plan|
        capability = rate_plan.channex_capability(room_type: room_type)
        unless capability.supported?
          assignment = room_type.room_type_rate_plans.find_by!(rate_plan: rate_plan)
          if !rate_plan.kind.in?(RatePlan::DISTRIBUTABLE_KINDS) && !live_mapping?(assignment.channel_mapping)
            next true
          end

          skipped << skipped_plan(rate_plan, room_type, capability.reason)
          next true
        end

        sync_rate_plan(rate_plan, room_type: room_type).present?
      end

      { ok: ok, skipped: skipped }
    end

    # Returns nil when the occupancy ladder cannot be resolved, which leaves
    # sync_rate_plan to report the failure rather than raise.
    def default_rate_plan_options(rate_plan, room_type: nil)
      room_type ||= rate_plan.room_types.first
      max_occupancy = [ room_type&.max_adults.to_i, 1 ].max
      return [ { occupancy: max_occupancy, is_primary: true, rate: 0 } ] unless rate_plan.sell_mode == "per_person"

      assignment = rate_plan.room_type_rate_plans.find_by!(room_type: room_type)
      # An assignment can derive its ladder from the category's standard plan
      # instead of holding its own occupancy rows, so the starting prices come
      # from the same resolver the ARI push uses. Passing no room rates keeps
      # daily overrides out of the structure payload.
      ladder = resolved_channex_rate(
        rate_plan: rate_plan,
        room_type: room_type,
        room_type_rate_plan: assignment,
        date: Date.current,
        rates: []
      )
      return nil if ladder.nil?

      # Channex requires exactly one primary option. The PMS base occupancy
      # is authoritative, bounded to the capacity of this assignment.
      primary = rate_plan.base_occupancy.to_i.clamp(1, max_occupancy)
      ladder.map do |occupancy, rate|
        { occupancy: occupancy, is_primary: occupancy == primary, rate: rate }
      end
    end

    def map_amenities_to_channex_ids(amenity_slugs, type)
      return [] if amenity_slugs.blank?

      map = Amenity.lookup_map(type)
      amenity_slugs.map { |slug| map[slug]&.fetch(:channex_id, nil) }.compact
    end

    def format_money(value)
      format("%.2f", value.to_d)
    end

    def response_warnings(response)
      response.dig("meta", "warnings").to_a
    end

    def raise_if_retryable_response!(response, operation)
      return unless response[:retryable] || response["retryable"]

      raise Channex::Client::RetryableRequestError,
        "#{operation} retryable failure: #{response[:details] || response['details'] || response}"
    end

    def success(message, task_ids: {})
      SyncResult.build(:full_success, message, task_ids: task_ids)
    end

    def partial_success(message, warnings:, task_ids: {})
      SyncResult.build(:partial_success, message, warnings: warnings, task_ids: task_ids)
    end

    def availability_only(message, warnings:, task_ids: {})
      SyncResult.build(:availability_only, message, warnings: warnings, task_ids: task_ids)
    end

    def unsupported_pricing(message, warnings: [])
      SyncResult.build(:unsupported_pricing, message, warnings: warnings)
    end

    def failure(message, warnings: [], task_ids: {})
      SyncResult.build(:failure, message, warnings: warnings, task_ids: task_ids)
    end

    def record_sync_result(result)
      ActiveSupport::Notifications.instrument(
        "channex.ari_sync",
        hotel_id: @hotel.id,
        status: result.status,
        message: result.message,
        warnings: result.warnings,
        skipped_plan_ids: result.warnings.filter_map do |warning|
          warning[:rate_plan_id] || warning["rate_plan_id"] if warning.is_a?(Hash)
        end.uniq,
        task_ids: result.task_ids
      )
      Rails.logger.info(
        "Channex ARI result status=#{result.status} hotel_id=#{@hotel.id} " \
        "task_ids=#{result.task_ids.to_json} warnings=#{result.warnings.to_json}"
      )
      result
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
        next if ext_rt_id.to_s.start_with?("pending")

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
  end
end
