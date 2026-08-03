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

        if existing_group && group.revision_number.to_i >= @data[:revision_number].to_i
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
        children.each { |booking| Bookings::InventoryManager.new(booking).deduct if inventory_held_status?(booking.status) }

        Bookings::RecordAuditLog.call!(
          auditable: group,
          action_type: existing_group ? "external_modification" : "external_creation",
          source: "channel_manager",
          old_value: old_audit_value,
          new_value: audit_values(group, children),
          metadata: {
            "source" => group.source,
            "external_reference" => group.external_reference,
            "revision" => group.revision_number
          }
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

    def desired_units(children)
      units = Array(@data[:rooms]).flat_map do |room_item|
        quantity = [ room_item[:quantity].to_i, 1 ].max
        unit_amount = (room_item[:amount].to_d / quantity).round(2)
        Array.new(quantity) do
          {
            room_type: room_item[:room_type],
            rate_plan: room_item[:rate_plan],
            amount: unit_amount
          }
        end
      end
      return units if units.any? || @data[:status] != "cancelled"

      children.reject { |booking| booking.status == "cancelled" }.filter_map do |booking|
        room = booking.booking_rooms.first
        next unless room

        { room_type: room.room_type, rate_plan: room.rate_plan, amount: room.subtotal }
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
        sync_guest(booking)
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
        adults: @data[:adults] || 1,
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
      room.update!(room_type: unit[:room_type], rate_plan: unit[:rate_plan], subtotal: unit[:amount])
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

    def payment_status_for(booking, incoming_status)
      status = @data[:payment_status].presence || @data.dig(:payment, :status).presence
      return status if Booking::PAYMENT_STATUSES.include?(status.to_s)
      return "refunded" if incoming_status == "cancelled" && booking.payment_status == "captured"

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

    def sync_guest(booking)
      attrs = guest_sync_attributes
      guest = find_existing_guest_for_sync(attrs)
      if guest.blank? && Guest.new(attrs).valid?
        result = GuestArrival::CreateOrMatchGuest.new(attrs).call
        guest = result.guest if result.success?
      end
      booking.booking_guests.create!(guest: guest, is_primary: true) if guest && !booking.booking_guests.exists?(guest: guest)
    end

    def guest_sync_attributes
      {
        name: @data[:guest_details][:name], email: @data[:guest_details][:email],
        phone: @data[:guest_details][:phone], government_id: @data[:guest_details][:government_id],
        gender: @data[:guest_details][:gender], country: @data[:guest_details][:country],
        document_type: @data[:guest_details][:document_type], date_of_birth: @data[:guest_details][:date_of_birth]
      }
    end

    def find_existing_guest_for_sync(attrs)
      return Guest.find_by(government_id: attrs[:government_id].to_s.downcase.strip) if attrs[:government_id].present?
      return Guest.find_by(email: attrs[:email].to_s.downcase.strip) if attrs[:email].present?
      return Guest.find_by(phone: attrs[:phone].to_s.strip) if attrs[:phone].present?

      nil
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
