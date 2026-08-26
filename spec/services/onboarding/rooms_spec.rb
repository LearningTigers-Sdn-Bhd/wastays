# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::SaveRooms do
  let(:hotel) { create(:hotel, status: "setup") }
  let(:actor) { create(:user, account: hotel.account) }

  def resolve_prerequisites!
    Onboarding::InitializeProgress.new(hotel: hotel).call
    %w[property_profile property_photos team_setup taxes_fees room_revenue].each do |key|
      hotel.onboarding_sections.find_by!(section_key: key).update!(state: "complete")
    end
  end

  def room_entry(overrides = {})
    {
      "client_key" => "draft-1",
      "name" => "Deluxe Twin",
      "max_adults" => "2",
      "max_children" => "1",
      "quantity" => "2",
      "no_smoking" => "1",
      "no_pets" => "1",
      "amenities" => [],
      "room_number_mode" => "range",
      "room_numbers" => [ "101", "102" ]
    }.merge(overrides)
  end

  def save(entries:, complete: false)
    described_class.new(hotel: hotel, actor: actor, entries: entries, complete: complete).call
  end

  before { resolve_prerequisites! }

  it "creates real rooms atomically with internal zero pricing and inverse policies" do
    result = save(entries: { "draft-1" => room_entry }, complete: true)

    expect(result.success?).to be(true)
    room = hotel.room_types.sole
    expect(room).to have_attributes(
      name: "Deluxe Twin", quantity: 2, max_adults: 2, max_children: 1,
      base_price: 0.to_d, smoking_allowed: false, pets_allowed: false
    )
    expect(room.room_numbers).to eq([ "101", "102" ])
    expect(result.section).to have_attributes(state: "complete")
    expect(result.section.decision_metadata).to include("pricing_deferred" => true)
    expect(result.section.decision_metadata).not_to have_key("placeholder")
  end

  it "rolls every row back when one row is invalid" do
    result = save(entries: {
      "first" => room_entry("client_key" => "first"),
      "second" => room_entry("client_key" => "second", "name" => "", "max_adults" => "0")
    })

    expect(result.success?).to be(false)
    expect(result.error).to start_with("Room 2:")
    expect(hotel.room_types).to be_empty
  end

  it "preserves an existing room's price while updating operational fields" do
    room = create(:room_type, hotel: hotel, base_price: 325, quantity: 1, room_numbers: [])

    result = save(entries: { "room" => room_entry(
      "id" => room.id.to_s,
      "quantity" => "3",
      "room_numbers" => [],
      "room_number_mode" => "range"
    ) })

    expect(result.success?).to be(true)
    expect(room.reload).to have_attributes(quantity: 3, base_price: 325.to_d)
  end

  it "does not persist any rows when numbering is invalid" do
    result = save(entries: { "draft" => room_entry("quantity" => "3", "room_numbers" => [ "101", "101" ]) })

    expect(result.success?).to be(false)
    expect(result.error).to include("Room numbers must be unique", "exactly one number")
    expect(hotel.room_types).to be_empty
  end

  it "requires at least one operational room only when completing" do
    draft = save(entries: {}, complete: false)
    complete = save(entries: {}, complete: true)

    expect(draft.success?).to be(true)
    expect(draft.section.state).to eq("in_progress")
    expect(complete.success?).to be(false)
    expect(complete.error).to include("Add at least one room category")
  end

  it "invalidates completed room and rate progress after a structural change without changing rates" do
    room = create(:room_type, hotel: hotel, quantity: 1, max_adults: 2, max_children: 1, room_numbers: [])
    rooms_section = hotel.onboarding_sections.find_by!(section_key: "rooms")
    rates_section = hotel.onboarding_sections.find_by!(section_key: "rates_availability")
    rooms_section.update!(state: "complete")
    rates_section.update!(state: "complete")
    rate_plan_count = hotel.rate_plans.count
    room_rate_count = room.room_rates.count

    result = save(entries: { "room" => room_entry(
      "id" => room.id.to_s,
      "quantity" => "2",
      "room_numbers" => []
    ) })

    expect(result.success?).to be(true)
    expect(rooms_section.reload.state).to eq("needs_attention")
    expect(rates_section.reload.state).to eq("needs_attention")
    expect(hotel.rate_plans.count).to eq(rate_plan_count)
    expect(room.room_rates.reload.count).to eq(room_rate_count)
    expect(hotel.onboarding_audit_events.where(event_type: "invalidated", section_key: "rates_availability")).to exist
  end

  it "preserves completed progress after name, amenity, and policy changes" do
    room = create(:room_type, hotel: hotel, quantity: 1, max_adults: 2, max_children: 1, room_numbers: [])
    amenity = Hotel::CATEGORIZED_ROOM_AMENITIES.first[:items].first[:id].to_s
    rooms_section = hotel.onboarding_sections.find_by!(section_key: "rooms")
    rates_section = hotel.onboarding_sections.find_by!(section_key: "rates_availability")
    rooms_section.update!(state: "complete")
    rates_section.update!(state: "complete")

    result = save(entries: { "room" => room_entry(
      "id" => room.id.to_s,
      "name" => "Garden Twin",
      "quantity" => "1",
      "room_numbers" => [],
      "amenities" => [ amenity ],
      "no_smoking" => "0",
      "no_pets" => "0"
    ) })

    expect(result.success?).to be(true)
    expect(rooms_section.reload.state).to eq("complete")
    expect(rates_section.reload.state).to eq("complete")
    expect(room.reload).to have_attributes(name: "Garden Twin", smoking_allowed: true, pets_allowed: true)
    expect(room.amenities).to eq([ amenity ])
  end

  it "rejects a forged room id without changing either hotel" do
    foreign_room = create(:room_type)

    result = save(entries: { "forged" => room_entry("id" => foreign_room.id.to_s) })

    expect(result.success?).to be(false)
    expect(result.error).to include("do not belong")
    expect(foreign_room.reload.name).not_to eq("Deluxe Twin")
  end
end
