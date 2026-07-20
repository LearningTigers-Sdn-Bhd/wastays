# frozen_string_literal: true

class Api::V2::BookingsController < Api::V2::BaseController
  def show
    booking = find_booking
    group = booking&.group_booking || find_group

    unless booking || group
      render json: { error: "Booking not found or access denied" }, status: :not_found
      return
    end

    bookings = group ? group.bookings.includes(:hotel, booking_rooms: :room_type).to_a : [ load_booking(booking) ]
    render json: { api_version: "v2", reservation: reservation_payload(group, bookings) }
  end

  private

  def find_booking
    booking_scope.find_by(confirmation_token: params[:id]) || booking_scope.find_by(id: params[:id])
  end

  def find_group
    scope = GroupBooking.where(id: booking_scope.where.not(group_booking_id: nil).select(:group_booking_id))
    identifier = params[:id].to_s
    group_id = identifier.delete_prefix("group-") if identifier.start_with?("group-")
    group = scope.find_by(confirmation_token: identifier) ||
      scope.find_by(external_reference: identifier) ||
      scope.find_by(channel_manager_reference: identifier) ||
      scope.find_by(id: group_id)
    return group if group

    reservation_number = identifier[/\d{7}\z/]&.to_i
    scope.where(reservation_number:).detect { |candidate| candidate.formatted_reservation_number == identifier } if reservation_number
  end

  def load_booking(booking)
    booking_scope.includes(:hotel, booking_rooms: :room_type).find(booking.id)
  end

  def reservation_payload(group, bookings)
    primary = bookings.first
    payload = {
      identity: reservation_identity(group || primary),
      group: group_identity(group),
      hotel: hotel_payload(primary.hotel),
      status: group ? group.projected_status : primary.status,
      check_in: bookings.map(&:check_in).compact.min,
      check_out: bookings.map(&:check_out).compact.max,
      guest_name: primary.guest_name,
      guest_email: primary.guest_email,
      guest_phone: primary.guest_phone,
      adults: bookings.sum(&:adults),
      children: bookings.sum { |child| child.children.to_i },
      bookings: bookings.map { |child| booking_payload(child) }
    }

    legacy = legacy_payload(group, bookings)
    payload[:legacy] = legacy if legacy
    payload
  end

  def reservation_identity(record)
    {
      type: record.is_a?(GroupBooking) ? "group_booking" : "booking",
      id: record.id,
      confirmation_token: record.confirmation_token,
      reference: record.formatted_reservation_number,
      lookup: record.is_a?(GroupBooking) ? "group-#{record.id}" : record.id.to_s
    }
  end

  def group_identity(group)
    return unless group

    reservation_identity(group).merge(
      name: group.name,
      external_reference: group.external_reference,
      channel_manager_reference: group.channel_manager_reference
    )
  end

  def booking_payload(booking)
    room = booking.booking_rooms.first
    {
      id: booking.id,
      confirmation_token: booking.confirmation_token,
      reference: booking.formatted_reservation_number,
      group_position: booking.group_position,
      status: booking.status,
      check_in: booking.check_in,
      check_out: booking.check_out,
      guest_name: booking.guest_name,
      guest_email: booking.guest_email,
      guest_phone: booking.guest_phone,
      adults: booking.adults,
      children: booking.children,
      room: room_payload(room)
    }
  end

  def room_payload(room)
    return unless room

    {
      id: room.id,
      room_number: room.room_number,
      subtotal: room.subtotal,
      room_type: {
        id: room.room_type.id,
        name: room.room_type.name
      }
    }
  end

  def hotel_payload(hotel)
    hotel.as_json(only: [ :id, :name, :city, :latitude, :longitude, :address ])
  end

  def legacy_payload(group, bookings)
    scope = LegacyBookingSplitLineage.where(child_booking_id: bookings.map(&:id))
    scope = scope.where(group_booking_id: group.id) if group
    lineages = scope.includes(:legacy_booking).order(:child_booking_id).to_a
    return if lineages.empty?

    legacy_booking = lineages.first.legacy_booking
    {
      legacy_booking_id: legacy_booking.id,
      legacy_confirmation_token: legacy_booking.confirmation_token,
      legacy_reference: legacy_booking.formatted_reservation_number,
      split_batch_id: lineages.first.batch_id,
      lineages: lineages.map do |lineage|
        {
          child_booking_id: lineage.child_booking_id,
          booking_room_id: lineage.booking_room_id,
          anchor: lineage.anchor,
          review_status: lineage.review_status
        }
      end
    }
  end
end
