# frozen_string_literal: true

require "rails_helper"

# Guards the co-located constants in view_models.rb and inventory.rb. These files each define
# several constants, so only one per file is Zeitwerk-autoloadable by name; the rest rely on
# stay_view.rb requiring the file. Referencing a struct directly (as components and specs do)
# must resolve even with eager loading off, which is the default for local rspec runs.
RSpec.describe "StayView namespace loading" do
  it "resolves every co-located view model and inventory record struct" do
    constants = %i[
      TrackRange Occupancy DayCell BookingSegment OperationalSegment RoomRow StandardRate RoomGroup RoomTypeOption
      FilterState StatusCounts Capabilities Board
      Inventory RoomTypeRecord BookingRecord RoomStatusRecord RoomBlockRecord StandardRateRecord
    ]

    expect { constants.each { |name| StayView.const_get(name) } }.not_to raise_error
  end
end
