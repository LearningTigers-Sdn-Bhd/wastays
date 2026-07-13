# frozen_string_literal: true

require "rails_helper"

RSpec.describe "booking folio room scope migration" do
  let(:connection) { ActiveRecord::Base.connection }

  it "adds a nullable indexed booking room foreign key" do
    column = connection.columns(:booking_folios).find { |candidate| candidate.name == "booking_room_id" }
    foreign_key = connection.foreign_keys(:booking_folios).find { |candidate| candidate.column == "booking_room_id" }

    expect(column).not_to be_nil
    expect(column.null).to be(true)
    expect(connection.index_exists?(:booking_folios, :booking_room_id)).to be(true)
    expect(foreign_key&.to_table).to eq("booking_rooms")
  end

  it "enforces separate booking-level and room-level primary indexes" do
    indexes = connection.indexes(:booking_folios).index_by(&:name)
    booking_level = indexes.fetch("idx_booking_folios_primary_at_booking_level")
    room_level = indexes.fetch("idx_booking_folios_primary_per_room")

    expect(booking_level.unique).to be(true)
    expect(booking_level.columns).to eq([ "booking_id" ])
    expect(booking_level.where).to include("is_primary").and include("booking_room_id IS NULL")
    expect(room_level.unique).to be(true)
    expect(room_level.columns).to eq(%w[booking_id booking_room_id])
    expect(room_level.where).to include("is_primary").and include("booking_room_id IS NOT NULL")
  end
end
