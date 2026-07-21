# frozen_string_literal: true

require "ostruct"

module Bookings
  class SplitLegacyMultiRoom
    MONEY_COLUMNS = %w[total_amount margin_amount net_amount tourism_tax_amount].freeze
    CHILD_CLEARED_COLUMNS = %w[
      id created_at updated_at confirmation_token reservation_number receipt_number guest_registration_number
      folio_account_reference group_booking_id group_position payout_batch_id payout_at payout_reference
      external_reference channel_manager_reference tourism_tax_voucher_number
    ].freeze
    GUEST_LINK_COLUMNS = %w[
      guest_id is_primary role name_snapshot email_snapshot phone_snapshot government_id_snapshot
      gender_snapshot country_snapshot document_type_snapshot date_of_birth_snapshot
    ].freeze

    def self.call(booking:, actor: nil, batch_id: SecureRandom.uuid, metadata: {})
      new(booking: booking, actor: actor, batch_id: batch_id, metadata: metadata).call
    end

    def initialize(booking:, actor:, batch_id:, metadata:)
      @booking = booking
      @actor = actor
      @batch_id = batch_id
      @metadata = metadata.to_h.deep_stringify_keys
    end

    def call
      result = nil
      Booking.transaction do
        @booking.lock!
        existing = LegacyBookingSplitLineage.find_by(legacy_booking_id: @booking.id)
        if existing
          result = success(existing.group_booking, existing.batch_id, idempotent: true)
          next
        end

        error = validation_error
        raise ActiveRecord::Rollback if error && (result = failure(error))

        rooms = @booking.booking_rooms.order(:id).lock.to_a
        @review_reasons = review_reasons
        group = create_group!
        allocations = monetary_allocations(rooms)

        @booking.update_columns(
          group_booking_id: group.id,
          group_position: 1,
          external_reference: nil,
          channel_manager_reference: nil,
          revision_number: 0,
          **allocations.fetch(rooms.first.id)
        )
        create_lineage!(group: group, child: @booking, room: rooms.first, anchor: true)

        rooms.drop(1).each.with_index(2) do |room, position|
          child = create_child!(group: group, position: position, allocation: allocations.fetch(room.id))
          room.update_columns(booking_id: child.id, updated_at: Time.current)
          copy_guest_links!(child)
          create_lineage!(group: group, child: child, room: room, anchor: false)
        end

        record_audit!(group, rooms)
        result = success(group, @batch_id, idempotent: false)
      end
      result
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      failure(e.message)
    end

    private

    def validation_error
      return "Booking is already assigned to a group." if @booking.group_booking_id.present?
      return "Booking must contain at least two room stays." if @booking.booking_rooms.count < 2

      nil
    end

    def finance_blocked?
      @booking.payout_batch_id.present? || @booking.deposits.exists? || @booking.payment_transactions.exists? ||
        @booking.refund_request.present? || FolioTransaction.joins(:booking_folio).where(booking_folios: { booking_id: @booking.id }).exists?
    end

    def external_blocked?
      @booking.external_reference.present? || @booking.channel_manager_reference.present? ||
        @booking.source.present? && !@booking.source.in?(%w[internal walk_in])
    end

    def create_group!
      GroupBooking.create!(
        hotel: @booking.hotel,
        organizer_guest: @booking.primary_guest,
        name: "Legacy reservation #{@booking.confirmation_token}",
        status: group_status,
        source: "legacy_split",
        external_reference: @booking.external_reference,
        channel_manager_reference: @booking.channel_manager_reference,
        revision_number: @booking.revision_number,
        default_check_in: @booking.check_in.to_date,
        default_check_out: @booking.check_out.to_date,
        metadata: @metadata.merge("legacy_booking_id" => @booking.id, "split_batch_id" => @batch_id)
      )
    end

    def create_child!(group:, position:, allocation:)
      attributes = @booking.attributes.except(*CHILD_CLEARED_COLUMNS)
      attributes.merge!(allocation.stringify_keys)
      attributes.merge!(
        "group_booking_id" => group.id,
        "group_position" => position,
        "confirmation_token" => next_confirmation_token,
        "reservation_number" => HotelCounter.increment!(hotel: @booking.hotel, type: "reservation"),
        "receipt_number" => HotelCounter.increment!(hotel: @booking.hotel, type: "receipt"),
        "guest_registration_number" => HotelCounter.increment!(hotel: @booking.hotel, type: "guest_registration"),
        "external_reference" => nil,
        "channel_manager_reference" => nil,
        "revision_number" => 0,
        "payment_status" => "pending",
        "payout_status" => nil,
        "deposit_status" => nil,
        "pre_checkin_status" => nil,
        "created_at" => Time.current,
        "updated_at" => Time.current
      )

      id = Booking.insert_all!([ attributes ], returning: %w[id]).rows.first.first
      Booking.find(id)
    end

    def next_confirmation_token
      holder = Struct.new(:confirmation_token).new
      DocumentIdentifiers::HotelReferences.assign_confirmation_token(holder, unique_against: [ Booking, GroupBooking ])
      holder.confirmation_token
    end

    def monetary_allocations(rooms)
      weights = allocation_weights(rooms)
      allocations = rooms.to_h { |room| [ room.id, {} ] }

      MONEY_COLUMNS.each do |column|
        original = @booking.public_send(column)
        next if original.nil?

        children_total = 0.to_d
        rooms.drop(1).each do |room|
          amount = (original.to_d * weights.fetch(room.id)).round(2)
          allocations.fetch(room.id)[column] = amount
          children_total += amount
        end
        allocations.fetch(rooms.first.id)[column] = original.to_d - children_total
      end

      allocate_json_amounts!(allocations, rooms, weights, "tax_lines")
      allocate_json_amounts!(allocations, rooms, weights, "tax_posting_snapshot")
      allocations
    end

    def allocation_weights(rooms)
      total = rooms.sum { |room| room.subtotal.to_d }
      return rooms.to_h { |room| [ room.id, 1.to_d / rooms.size ] } unless total.positive?

      rooms.to_h { |room| [ room.id, room.subtotal.to_d / total ] }
    end

    def allocate_json_amounts!(allocations, rooms, weights, column)
      source = @booking.public_send(column)
      child_values = {}
      rooms.drop(1).each do |room|
        child_values[room.id] = scale_json_amounts(source, weights.fetch(room.id))
        allocations.fetch(room.id)[column] = child_values.fetch(room.id)
      end
      allocations.fetch(rooms.first.id)[column] = subtract_json_amounts(source, child_values.values)
    end

    def scale_json_amounts(value, weight)
      case value
      when Array then value.map { |item| scale_json_amounts(item, weight) }
      when Hash
        value.to_h do |key, item|
          scaled = key.to_s.end_with?("amount") && item.is_a?(Numeric) ? (item.to_d * weight).round(2) : scale_json_amounts(item, weight)
          [ key, scaled ]
        end
      else value
      end
    end

    def subtract_json_amounts(source, children)
      case source
      when Array
        source.each_index.map { |index| subtract_json_amounts(source[index], children.map { |child| child[index] }) }
      when Hash
        source.to_h do |key, value|
          child_values = children.map { |child| child[key] }
          remainder = if key.to_s.end_with?("amount") && value.is_a?(Numeric)
            value.to_d - child_values.sum(&:to_d)
          else
            subtract_json_amounts(value, child_values)
          end
          [ key, remainder ]
        end
      else source
      end
    end

    def copy_guest_links!(child)
      rows = @booking.booking_guests.map do |link|
        link.attributes.slice(*GUEST_LINK_COLUMNS).merge(
          "booking_id" => child.id,
          "created_at" => Time.current,
          "updated_at" => Time.current
        )
      end
      BookingGuest.insert_all!(rows) if rows.any?
    end

    def create_lineage!(group:, child:, room:, anchor:)
      LegacyBookingSplitLineage.create!(
        legacy_booking: @booking,
        group_booking: group,
        child_booking: child,
        booking_room: room,
        anchor: anchor,
        review_status: @review_reasons.any? ? "pending" : "approved",
        review_reason: @review_reasons.presence&.to_sentence || "automated legacy multi-room split",
        batch_id: @batch_id,
        metadata: @metadata
      )
    end

    def group_status
      return "cancelled" if @booking.status == "cancelled"
      return "completed" if @booking.status.in?(%w[completed no_show])

      "active"
    end

    def review_reasons
      reasons = []
      reasons << "historical financial custody remains on anchor child" if finance_blocked?
      reasons << "external reservation identity moved to group" if external_blocked?
      reasons
    end

    def record_audit!(group, rooms)
      Bookings::RecordAuditLog.call!(
        auditable: @booking,
        user: @actor,
        action_type: "legacy_multi_room_split",
        category: "other",
        source: "legacy_split",
        new_value: { group_booking_id: group.id, booking_ids: group.bookings.pluck(:id) },
        metadata: @metadata.merge("batch_id" => @batch_id, "booking_room_ids" => rooms.map(&:id))
      )
    end

    def success(group, batch_id, idempotent:)
      OpenStruct.new(success?: true, group_booking: group, bookings: group.bookings.to_a, batch_id: batch_id, idempotent?: idempotent, error: nil)
    end

    def failure(message)
      OpenStruct.new(success?: false, group_booking: nil, bookings: [], batch_id: nil, idempotent?: false, error: message)
    end
  end
end
