# frozen_string_literal: true

require "rails_helper"

# The rooms table is the source of truth. Removing a room number from Room
# Inventory archives its physical room, and every operational read must lose
# that room in the same step.
RSpec.describe "Physical rooms are authoritative", frozen_time: Time.zone.local(2026, 8, 15, 12) do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:, accounting_business_date: selected_date) }
  let(:selected_date) { Date.new(2026, 8, 15) }
  let(:capabilities) do
    StayView::Capabilities.new(**StayView::Capabilities.members.index_with { false }.merge(view_board: true))
  end
  let!(:room_type) do
    create(:room_type, hotel:, name: "Deluxe", room_number_mode: "custom", quantity: 2, room_numbers: %w[101 102])
  end

  def housekeeping_numbers
    HousekeepingTasks::BoardBuilder.new(hotel:, date: selected_date).call.map { |entry| entry[:room_number] }
  end

  def stay_view_numbers
    StayView::LoadInventory.call(
      hotel:,
      date_window: StayView::DateWindow.new(hotel:, start_date: selected_date, days: 1),
      capabilities:
    ).room_types.flat_map(&:room_numbers)
  end

  def available_numbers
    Bookings::AvailableRoomNumbers.new(
      hotel:, room_type:, check_in: selected_date, check_out: selected_date + 1.day
    ).call
  end

  it "shows every room of the category before anything changes" do
    expect(housekeeping_numbers).to contain_exactly("101", "102")
    expect(stay_view_numbers).to contain_exactly("101", "102")
    expect(available_numbers).to contain_exactly("101", "102")
  end

  it "drops an archived room from Housekeeping, Stay View, and availability" do
    room_type.update!(quantity: 1, room_numbers: %w[101])
    Rooms::SyncFromRoomType.call!(room_type:)

    expect(hotel.rooms.find_by!(number: "102")).to be_archived
    expect(housekeeping_numbers).to contain_exactly("101")
    expect(stay_view_numbers).to contain_exactly("101")
    expect(available_numbers).to contain_exactly("101")
  end

  it "brings a restored room back to every board" do
    room_type.update!(quantity: 1, room_numbers: %w[101])
    Rooms::SyncFromRoomType.call!(room_type:)
    room_type.update!(quantity: 2, room_numbers: %w[101 102])
    Rooms::SyncFromRoomType.call!(room_type:)

    expect(hotel.rooms.find_by!(number: "102")).to be_active
    expect(housekeeping_numbers).to contain_exactly("101", "102")
    expect(stay_view_numbers).to contain_exactly("101", "102")
    expect(available_numbers).to contain_exactly("101", "102")
  end

  it "ignores a room number that Room Inventory holds without a physical room" do
    hotel.rooms.find_by!(number: "102").destroy!

    expect(room_type.reload.room_numbers).to contain_exactly("101", "102")
    expect(housekeeping_numbers).to contain_exactly("101")
    expect(stay_view_numbers).to contain_exactly("101")
    expect(available_numbers).to contain_exactly("101")
  end
end
