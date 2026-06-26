# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolioRoutingRule do
  let(:booking) { create(:booking) }
  let(:hotel) { booking.hotel }
  let(:transaction_code) { create(:transaction_code, hotel: hotel) }
  let(:target_folio) { create(:booking_folio, :secondary, booking: booking, hotel: hotel) }

  it "is valid when hotel, booking, transaction code, and target folio align" do
    rule = described_class.new(
      hotel: hotel,
      booking: booking,
      transaction_code: transaction_code,
      target_folio: target_folio
    )

    expect(rule).to be_valid
  end

  it "requires core associations" do
    rule = described_class.new

    expect(rule).not_to be_valid
    expect(rule.errors[:hotel]).to be_present
    expect(rule.errors[:booking]).to be_present
    expect(rule.errors[:transaction_code]).to be_present
    expect(rule.errors[:target_folio]).to be_present
  end

  it "requires booking to belong to the same hotel" do
    other_hotel = create(:hotel)
    rule = described_class.new(hotel: other_hotel, booking: booking, transaction_code: create(:transaction_code, hotel: other_hotel), target_folio: target_folio)

    expect(rule).not_to be_valid
    expect(rule.errors[:booking]).to include("must belong to the same hotel")
  end

  it "requires target folio to belong to the same booking" do
    other_booking = create(:booking, hotel: hotel)
    other_folio = create(:booking_folio, booking: other_booking, hotel: hotel)
    rule = described_class.new(hotel: hotel, booking: booking, transaction_code: transaction_code, target_folio: other_folio)

    expect(rule).not_to be_valid
    expect(rule.errors[:target_folio]).to include("must belong to the same booking")
  end

  it "requires target folio to belong to the same hotel" do
    other_hotel = create(:hotel)
    other_booking = create(:booking, hotel: other_hotel)
    other_folio = create(:booking_folio, booking: other_booking, hotel: other_hotel)
    rule = described_class.new(hotel: hotel, booking: booking, transaction_code: transaction_code, target_folio: other_folio)

    expect(rule).not_to be_valid
    expect(rule.errors[:target_folio]).to include("must belong to the same booking")
    expect(rule.errors[:target_folio]).to include("must belong to the same hotel")
  end

  it "requires transaction code to belong to the same hotel" do
    other_code = create(:transaction_code)
    rule = described_class.new(hotel: hotel, booking: booking, transaction_code: other_code, target_folio: target_folio)

    expect(rule).not_to be_valid
    expect(rule.errors[:transaction_code]).to include("must belong to the same hotel")
  end

  it "allows only one active rule per booking and transaction code" do
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: transaction_code, target_folio: target_folio)
    second_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, name: "Company Folio 2")
    duplicate = build(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: transaction_code, target_folio: second_folio)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:transaction_code_id]).to include("already has an active routing rule for this booking")
  end

  it "allows inactive historical rules for the same booking and transaction code" do
    create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: transaction_code, target_folio: target_folio, active: false)
    active_rule = build(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: transaction_code, target_folio: target_folio)

    expect(active_rule).to be_valid
  end
end
