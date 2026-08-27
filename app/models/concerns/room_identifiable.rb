# frozen_string_literal: true

# Gives an operational record the stable identity of a physical room.
#
# The record keeps `room_number` as the historical value: the number printed on
# a folio or a registration card must not change when a hotel renumbers a room.
# `room_id` answers the different question of which room the record is about,
# and it survives a rename.
#
# An archived room still matches. Archiving removes a room from the boards, not
# from history, and a restored room keeps every record that named it.
#
# The reference stays nullable. A record can name a room the hotel never had,
# and the stored number is then the only true statement about it.
module RoomIdentifiable
  extend ActiveSupport::Concern

  included do
    belongs_to :room, optional: true

    before_validation :assign_room_from_number
  end

  private

  # A model whose hotel is not its own column overrides this.
  def room_identity_hotel_id
    hotel_id
  end

  def assign_room_from_number
    return if room_id.present?

    hotel_id = room_identity_hotel_id
    number = room_number.to_s.strip
    return if hotel_id.blank? || number.blank?

    self.room_id = Room.where(hotel_id:, number:).pick(:id)
  end
end
