# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # Room policies. Occupancy, smoking, and pets come from the room type and
    # are read-only here. Below them the hotel writes the terms a column cannot
    # hold: the age of a child, cots, pet deposits, cleaning charges.
    class PolicyRoomsController < HotelPortal::GuestContent::PolicyDocumentsController
      self.policy_key = "room_terms"
      self.document_title = "Room Terms"
      self.notice = "Room terms saved."

      before_action :load_room_policies

      private

      def load_room_policies
        @room_policies = HotelPortal::GuestContent::RoomPolicyPresenter.new(@hotel)
      end

      def policy_path
        hotel_policy_rooms_path(@hotel)
      end
    end
  end
end
