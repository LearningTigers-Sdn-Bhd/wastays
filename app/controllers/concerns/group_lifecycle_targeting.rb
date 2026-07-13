# frozen_string_literal: true

module GroupLifecycleTargeting
  extend ActiveSupport::Concern

  BatchTargetError = Class.new(StandardError)

  ELIGIBLE_STATUSES = HotelPortal::BookingLifecycleTargetPresenter::ELIGIBLE_STATUSES.freeze

  private

  def lifecycle_target_presenter(action)
    HotelPortal::BookingLifecycleTargetPresenter.new(booking: @booking, action: action)
  end

  def selected_lifecycle_bookings(fallback_booking:, action:)
    ids = Array(params[:booking_ids]).reject(&:blank?).map(&:to_i).uniq
    return [ fallback_booking ] if ids.empty? && !group_lifecycle_targeting_submitted?(fallback_booking)

    raise BatchTargetError, "Group selection is only available for group bookings." if fallback_booking.group_booking_id.blank?

    bookings = fallback_booking.group_booking.bookings
      .includes(:hotel, :booking_folio, booking_rooms: :room_type, booking_guests: :guest)
      .where(id: ids)
      .order(:group_position, :id)
      .to_a

    raise BatchTargetError, "Select at least one booking." if bookings.empty?
    raise BatchTargetError, "One or more selected bookings are not part of this group." if bookings.size != ids.size

    ineligible = bookings.reject { |booking| lifecycle_booking_eligible?(booking, action) }
    if ineligible.any?
      labels = ineligible.map { |booking| lifecycle_booking_label(booking) }.to_sentence
      reason = ineligible.one? ? "it is" : "they are"
      raise BatchTargetError, "Cannot process #{labels} because #{reason} no longer eligible."
    end

    bookings
  end

  def selected_lifecycle_batch?(fallback_booking)
    group_lifecycle_targeting_submitted?(fallback_booking)
  end

  def group_lifecycle_targeting_submitted?(fallback_booking)
    fallback_booking.group_booking_id.present? && params.key?(:target_scope)
  end

  def lifecycle_booking_eligible?(booking, action)
    booking.status.in?(ELIGIBLE_STATUSES.fetch(action.to_sym))
  end

  def lifecycle_booking_label(booking)
    room = booking.booking_rooms.first
    room_number = room&.room_number.presence || "Unassigned room"
    guest_name = booking.booking_guests.find(&:primary?)&.name_snapshot.presence || booking.guest_name
    "#{room_number} - #{guest_name}"
  end

  def batch_lifecycle_notice(bookings, past_tense_action)
    "#{bookings.size} #{'booking'.pluralize(bookings.size)} #{past_tense_action}."
  end
end
