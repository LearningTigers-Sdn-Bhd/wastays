require "rails_helper"

RSpec.describe BookingRoom do
  describe "validations" do
    it "rejects a second room for the same booking" do
      booking = create(:booking)
      create(:booking_room, booking: booking)

      second_room = build(:booking_room, booking: booking)

      expect(second_room).not_to be_valid
      expect(second_room.errors.of_kind?(:booking_id, :taken)).to be(true)
    end
  end
end
