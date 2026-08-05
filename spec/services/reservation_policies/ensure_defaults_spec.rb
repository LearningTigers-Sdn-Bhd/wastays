# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReservationPolicies::EnsureDefaults do
  let(:hotel) { create(:hotel) }

  it "seeds all four stay-event policies" do
    described_class.call(hotel)

    expect(hotel.hotel_reservation_policies.pluck(:policy_type))
      .to match_array(%w[late_checkout early_departure no_show cancellation])
  end

  # The seeds exist to make today's hardcoded behaviour visible, not to change it.
  it "seeds no-show as one whole night, which is what FinalizeNoShow already bills" do
    described_class.call(hotel)

    no_show = hotel.hotel_reservation_policies.find_by(policy_type: "no_show")

    expect(no_show).to have_attributes(active: true, pricing_type: "nights", allow_amount_override: false)
    expect(no_show.rate_value).to eq(1)
  end

  it "seeds cancellation inactive, because cancelling charges nothing today" do
    described_class.call(hotel)

    expect(hotel.hotel_reservation_policies.find_by(policy_type: "cancellation")).not_to be_active
  end

  it "seeds late checkout and early departure as staff-entered amounts" do
    described_class.call(hotel)

    hotel.hotel_reservation_policies.where(policy_type: %w[late_checkout early_departure]).each do |policy|
      expect(policy).to have_attributes(active: true, pricing_type: "manual", allow_amount_override: true)
      expect(policy.rate_value).to be_nil
    end
  end

  it "links each policy to its own transaction code" do
    described_class.call(hotel)

    expect(hotel.hotel_reservation_policies.includes(:transaction_code).map { |p| p.transaction_code.system_key })
      .to match_array(%w[late_checkout_revenue early_departure_revenue no_show_revenue cancel_revenue])
  end

  it "is idempotent" do
    described_class.call(hotel)
    expect { described_class.call(hotel) }.not_to change(HotelReservationPolicy, :count)
  end

  it "leaves an edited policy alone on a later run" do
    described_class.call(hotel)
    policy = hotel.hotel_reservation_policies.find_by(policy_type: "late_checkout")
    policy.update!(active: false)

    described_class.call(hotel)

    expect(policy.reload).not_to be_active
  end

  it "creates the transaction codes it needs when the hotel has none" do
    hotel.transaction_codes.delete_all

    expect { described_class.call(hotel) }.to change { hotel.transaction_codes.count }.from(0)
    expect(hotel.hotel_reservation_policies.count).to eq(4)
  end
end
