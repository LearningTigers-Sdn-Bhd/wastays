# frozen_string_literal: true

require "ostruct"

module ChannelManagers
  class IngestGroupBookingService
    IngestionFailure = Class.new(StandardError)

    def initialize(booking_data:)
      @data = booking_data
      @hotel = @data[:hotel]
    end

    def call
      GroupBooking.transaction do
        @hotel.lock!
        group = find_or_initialize_group
        existing_group = group.persisted?
        group.lock! if existing_group
        children = existing_children(group)
        effective_check_in = @data[:check_in] || group.default_check_in || children.first&.check_in
        effective_check_out = @data[:check_out] || group.default_check_out || children.first&.check_out

        if effective_check_in.blank? || effective_check_out.blank?
          if @data[:status] == "cancelled" && !existing_group
            return OpenStruct.new(success?: true, bookings: [], group_booking: nil,
              message: "Ignored cancellation for unknown booking with no dates")
          end

          return failure("Missing mandatory dates (check-in/out)")
        end

        if existing_group && duplicate_or_older_revision?(group)
          return success_result(group, children, "Duplicate or older revision ignored")
        end

        old_audit_value = audit_values(group, children)
        previous_states = children.index_with { |booking| booking.slice("check_in", "check_out", "status") }
        children.each { |booking| Bookings::InventoryManager.new(booking).release if inventory_held_status?(booking.status) }

        incoming_status = resolved_status(effective_check_in, effective_check_out)
        units = desired_units(children)
        group.assign_attributes(group_attributes(effective_check_in, effective_check_out, incoming_status))
        group.save!

        children = reconcile_children!(group, children, units, effective_check_in, effective_check_out, incoming_status)
        persist_financial_snapshot!(group)
        children.each do |booking|
          Bookings::AutoAssignRoom.new(booking: booking, source: "channel_manager").call if inventory_held_status?(booking.status)
        end
        children.each { |booking| Bookings::InventoryManager.new(booking).deduct if inventory_held_status?(booking.status) }

        Bookings::RecordAuditLog.call!(
          auditable: group,
          action_type: existing_group ? "external_modification" : "external_creation",
          source: "channel_manager",
          old_value: old_audit_value,
          new_value: audit_values(group, children),
          metadata: audit_metadata({
            "source" => group.source,
            "external_reference" => group.external_reference,
            "revision" => group.revision_number
          })
        )

        children.each do |booking|
          dispatch_lifecycle_event(booking, previous_states[booking])
        end

        success_result(group, children)
      end
    rescue ActiveRecord::RecordInvalid, IngestionFailure => e
      failure(e.message)
    rescue => e
      failure("Ingestion failed: #{e.message}")
    end

    private

    def duplicate_or_older_revision?(group)
      revision_id = @data[:revision_id].to_s
      if revision_id.present? && !revision_id.match?(/\A\d+\z/)
        return true if OtaFinancialSnapshot.exists?(group_booking: group, provider_revision_id: revision_id)

        snapshot = OtaFinancialSnapshot.current.find_by(group_booking: group)
        if snapshot
          return true if snapshot.provider_revision_id == revision_id
          return true if @data[:revision_number].to_i < group.revision_number.to_i
        end
        return false
      end

      group.revision_number.to_i >= @data[:revision_number].to_i
    end

    def audit_metadata(metadata)
      metadata["currency_conversion"] = @data[:currency_conversion] if @data[:currency_conversion].present?
      metadata
    end

    def find_or_initialize_group
      @hotel.group_bookings.find_by(channel_manager_reference: @data[:channel_manager_reference]) ||
        @hotel.group_bookings.new
    end

    def existing_children(group)
      children = group.persisted? ? group.bookings.includes(booking_rooms: [ :room_type, :rate_plan ]).to_a : []
      return children if children.any?

      legacy_booking = @hotel.bookings.where(group_booking_id: nil)
        .find_by(channel_manager_reference: @data[:channel_manager_reference])
      legacy_booking ? [ legacy_booking ] : []
    end

    def group_attributes(check_in, check_out, status)
      {
        name: @data[:guest_details][:name],
        status: status == "cancelled" ? "cancelled" : "active",
        source: @data[:source],
        external_reference: @data[:external_reference],
        channel_manager_reference: @data[:channel_manager_reference],
        revision_number: @data[:revision_number],
        default_check_in: check_in.to_date,
        default_check_out: check_out.to_date
      }
    end

    def preserve_incomplete_cancellation_projection?
      @data[:status] == "cancelled" && @data[:financials].present? && @data.dig(:financials, :breakdown_complete) != true
    end

    def existing_cancellation_units(children)
      children.filter_map do |booking|
        room = booking.booking_rooms.first
        next unless room

        {
          room_type: room.room_type, rate_plan: room.rate_plan, amount: room.subtotal,
          occupancy: room.occupancy_snapshot, days: [], unit_index: 0, quantity: 1
        }
      end
    end

    def desired_units(children)
      return existing_cancellation_units(children) if preserve_incomplete_cancellation_projection?

      units = Array(@data[:rooms]).flat_map.with_index do |room_item, room_index|
        quantity = [ room_item[:quantity].to_i, 1 ].max
        unit_amount = (room_item[:amount].to_d / quantity).round(2)
        financial_room = Array(@data.dig(:financials, :rooms))[room_index]
        Array.new(quantity) do |unit_index|
          {
            room_type: room_item[:room_type],
            rate_plan: room_item[:rate_plan],
            amount: unit_amount,
            occupancy: occupancy_for_unit(financial_room&.dig(:occupancy) || room_item[:occupancy] || {}, quantity, unit_index),
            days: financial_room&.dig(:days) || [],
            unit_index: unit_index,
            quantity: quantity
          }
        end
      end
      allocate_aggregate_occupancy!(units) if units.any?
      return units if units.any? || @data[:status] != "cancelled"

      children.reject { |booking| booking.status == "cancelled" }.filter_map do |booking|
        room = booking.booking_rooms.first
        next unless room

        { room_type: room.room_type, rate_plan: room.rate_plan, amount: room.subtotal }
      end
    end

    def occupancy_for_unit(occupancy, quantity, unit_index)
      values = occupancy.to_h.symbolize_keys
      return values if quantity == 1

      allocated = %i[adults children infants].to_h do |key|
        quotient, remainder = values[key].to_i.divmod(quantity)
        [ key, quotient + (unit_index < remainder ? 1 : 0) ]
      end
      allocated[:allocation_source] = "room_aggregate"
      allocated
    end

    def allocate_aggregate_occupancy!(units)
      missing = units.select { |unit| %i[adults children infants].all? { |key| unit.dig(:occupancy, key).to_i.zero? } }
      return if missing.empty?

      %i[adults children infants].each do |key|
        provided = (units - missing).sum { |unit| unit.dig(:occupancy, key).to_i }
        total = [ @data[key].to_i - provided, 0 ].max
        quotient, remainder = total.divmod(missing.size)
        missing.each_with_index do |unit, index|
          unit[:occupancy] = unit[:occupancy].to_h.merge(key => quotient + (index < remainder ? 1 : 0))
          unit[:occupancy][:allocation_source] = "booking_aggregate"
        end
      end
    end

    def reconcile_children!(group, children, units, check_in, check_out, incoming_status)
      exact_matches = []
      historical_children = children.select { |booking| booking.status == "cancelled" }
      remaining_children = children.reject { |booking| booking.status == "cancelled" }
      remaining_units = units.dup

      units.each do |unit|
        booking = remaining_children.find { |candidate| room_matches?(candidate, unit) }
        next unless booking

        exact_matches << [ booking, unit ]
        remaining_children.delete(booking)
        remaining_units.delete_at(remaining_units.index(unit))
      end

      pairs = exact_matches + remaining_units.map { |unit| [ remaining_children.shift, unit ] }
      removed_children = remaining_children.compact
      group.bookings.update_all(group_position: nil)

      current_children = pairs.each_with_index.map do |(booking, unit), index|
        booking ||= group.bookings.build(hotel: @hotel)
        previous_status = booking.status if booking.persisted?
        child_status = resolved_child_status(previous_status, incoming_status)
        assign_status_transition!(booking, previous_status, child_status)
        booking.assign_attributes(child_attributes(group, booking, unit, check_in, check_out, child_status, index + 1))
        booking.channel_manager_reference = nil
        booking.external_reference = nil
        booking.revision_number = 0
        booking.save!
        sync_room!(booking, unit)
        ChannelManagers::InitializeBookingConnections.call!(
          booking: booking,
          guest_details: @data[:guest_details]
        )
        release_detected_no_show_rooms(booking) if previous_status == "no_show_detected" && booking.status == "cancelled"
        booking
      end

      removed_children.each_with_index do |booking, index|
        previous_status = booking.status
        assign_status_transition!(booking, previous_status, "cancelled")
        booking.update!(status: "cancelled", group_position: units.size + index + 1)
        release_detected_no_show_rooms(booking) if previous_status == "no_show_detected"
      end
      historical_children.each_with_index do |booking, index|
        booking.update_columns(group_position: units.size + removed_children.size + index + 1, updated_at: Time.current)
      end

      current_children + removed_children + historical_children
    end

    def room_matches?(booking, unit)
      room = booking.booking_rooms.first
      room && room.room_type_id == unit[:room_type]&.id && room.rate_plan_id == unit[:rate_plan]&.id
    end

    def child_attributes(group, booking, unit, check_in, check_out, child_status, position)
      {
        group_booking: group,
        group_position: position,
        guest_name: @data[:guest_details][:name],
        guest_email: @data[:guest_details][:email],
        guest_phone: @data[:guest_details][:phone],
        guest_country: @data[:guest_details][:country],
        check_in: Bookings::ScheduledStay.at_hotel_time(hotel: @hotel, value: check_in, kind: :check_in),
        check_out: Bookings::ScheduledStay.at_hotel_time(hotel: @hotel, value: check_out, kind: :check_out),
        status: child_status,
        adults: unit.dig(:occupancy, :adults).presence || @data[:adults].presence || 1,
        children: unit.dig(:occupancy, :children).presence || 0,
        total_amount: unit[:amount],
        currency: @data[:currency],
        source: @data[:source],
        payment_status: payment_status_for(booking, child_status),
        no_show_detected_business_date: child_status == "no_show_detected" ? check_in.to_date : nil
      }
    end

    def resolved_child_status(previous_status, incoming_status)
      return "no_show_detected" if previous_status == "no_show_detected" && incoming_status == "confirmed"

      incoming_status
    end

    def assign_status_transition!(booking, previous_status, incoming_status)
      return if previous_status.blank? || previous_status == incoming_status
      return if previous_status == "no_show_detected" && incoming_status == "confirmed"

      event = status_transition_event_for(previous_status, incoming_status)
      raise IngestionFailure, "Unsupported status transition from #{previous_status} to #{incoming_status}" unless event

      booking.status_transition_event = event
    end

    def sync_room!(booking, unit)
      rooms = booking.booking_rooms.to_a
      room = rooms.shift || booking.booking_rooms.build
      rooms.each(&:destroy!)
      room.update!(
        room_type: posted_nightly_history?(booking) && room.persisted? ? room.room_type : unit[:room_type],
        rate_plan: posted_nightly_history?(booking) && room.persisted? ? room.rate_plan : unit[:rate_plan],
        subtotal: unit[:amount],
        occupancy_snapshot: unit[:occupancy] || {}, nightly_rate_snapshot: nightly_snapshot_for(unit, booking, room.nightly_rate_snapshot)
      )
    end

    def nightly_snapshot_for(unit, booking, existing_snapshot)
      return existing_snapshot if preserve_incomplete_cancellation_projection?

      incoming = Array(unit[:days]).to_h do |day|
        amount = allocate_unit_amount(day[:converted_amount] || day[:amount], unit[:quantity], unit[:unit_index])
        [ day[:date].to_s, { "date" => day[:date].to_s, "price" => amount.to_d.to_s("F"),
          "currency" => @data[:currency], "source" => "ota_supplied" } ]
      end
      incoming.merge(existing_snapshot.to_h.slice(*posted_nightly_dates(booking)))
    end

    def posted_nightly_history?(booking)
      posted_nightly_dates(booking).any?
    end

    def posted_nightly_dates(booking)
      @posted_nightly_dates ||= {}
      @posted_nightly_dates[booking.id] ||= FolioTransaction.joins(:booking_folio)
        .where(booking_folios: { booking_id: booking.id }, voided_by_transaction_id: nil)
        .where("folio_transactions.metadata->>'nightly_charge_key' IS NOT NULL")
        .distinct.pluck(Arel.sql("COALESCE(folio_transactions.metadata->>'stay_date', folio_transactions.posting_date::text)"))
    end

    def allocate_unit_amount(amount, quantity, unit_index)
      unit = (amount.to_d / quantity).round(CurrencyCatalog.precision_for(@data[:currency]))
      unit_index == quantity - 1 ? amount.to_d - unit * (quantity - 1) : unit
    end

    def persist_financial_snapshot!(group)
      return unless @data.dig(:financials, :breakdown_complete) == true

      ChannelManagers::Financials::PersistSnapshot.call!(financials: @data[:financials], group_booking: group)
    end

    def inventory_insufficient?(check_in, check_out)
      required_by_room_type = Array(@data[:rooms]).each_with_object(Hash.new(0)) do |room_item, totals|
        totals[room_item[:room_type]] += [ room_item[:quantity].to_i, 1 ].max
      end
      (check_in.to_date...check_out.to_date).any? do |date|
        required_by_room_type.any? do |room_type, required|
          inventory = room_type.room_inventories.lock.find_by(date: date)
          !inventory || inventory.quantity < required
        end
      end
    end

    def resolved_status(check_in, check_out)
      return "cancelled" if @data[:status] == "cancelled"
      return "overbooked" if inventory_insufficient?(check_in, check_out)

      @data[:status]
    end

    def inventory_held_status?(status)
      status.in?(%w[confirmed no_show_detected checked_in due_out_detected checkout_required])
    end

    def status_transition_event_for(previous_status, new_status)
      case [ previous_status, new_status ]
      when [ "pending", "confirmed" ] then "confirm"
      when [ "pending", "cancelled" ], [ "confirmed", "cancelled" ], [ "overbooked", "cancelled" ], [ "no_show_detected", "cancelled" ] then "cancel"
      when [ "confirmed", "overbooked" ] then "mark_overbooked"
      when [ "overbooked", "confirmed" ] then "resolve_overbooking"
      end
    end

    def payment_status_for(booking, _incoming_status)
      status = @data[:payment_status].presence || @data.dig(:payment, :status).presence
      return status if Booking::PAYMENT_STATUSES.include?(status.to_s)
      booking.payment_status.presence || "pending"
    end

    def release_detected_no_show_rooms(booking)
      result = Bookings::ReleaseAssignedRooms.call(
        booking: booking,
        user: nil,
        event_type: "no_show_detection_cancelled",
        reason: "Channel manager cancelled booking with detected no-show",
        metadata: { "source" => "channel_manager", "external_reference" => @data[:external_reference] }
      )
      raise IngestionFailure, result.error unless result.success?
    end

    def dispatch_lifecycle_event(booking, previous_state)
      event = if previous_state.nil?
        :booking_confirmed if booking.status == "confirmed"
      elsif booking.status == "cancelled" && previous_state["status"] != "cancelled"
        :booking_cancelled
      elsif previous_state["check_in"] != booking.check_in || previous_state["check_out"] != booking.check_out || previous_state["status"] != booking.status
        :booking_updated
      end
      return unless event

      Bookings::WebhookTriggerService.new(booking).trigger(event)
      Notifications::Dispatcher.new(event: event, booking: booking).call
    end

    def audit_values(group, children)
      rooms = children.filter_map do |booking|
        room = booking.booking_rooms.first
        next unless room

        [ room.room_type&.name || "Room category not provided", room.rate_plan&.name ].compact.join(" - ")
      end
      room_summaries = rooms.tally.map { |summary, count| count > 1 ? "#{count}x #{summary}" : summary }

      {
        "guest_name" => children.first&.guest_name || @data[:guest_details][:name],
        "check_in" => group.default_check_in,
        "check_out" => group.default_check_out,
        "status" => group.status,
        "total_amount" => children.sum { |booking| booking.total_amount.to_d },
        "currency" => children.first&.currency || @data[:currency],
        "rooms" => room_summaries
      }
    end

    def success_result(group, children, message = nil)
      bookings = children.sort_by { |booking| [ booking.group_position || Float::INFINITY, booking.id || Float::INFINITY ] }
      OpenStruct.new(success?: true, booking: bookings.first, bookings: bookings, group_booking: group, message: message)
    end

    def failure(message)
      OpenStruct.new(success?: false, booking: nil, bookings: [], group_booking: nil, message: message)
    end
  end
end
