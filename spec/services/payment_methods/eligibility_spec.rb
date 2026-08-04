require "rails_helper"

RSpec.describe PaymentMethods::Eligibility do
  let(:hotel) { create(:hotel) }

  def method_for(purpose)
    PaymentMethods::EnsureDefaults.call(hotel)
    hotel.hotel_payment_methods.active.find_by!(guest_advance: purpose == :guest_advance)
  end

  it "resolves a configured method for its own purpose" do
    method = method_for(:guest_advance)

    result = described_class.call(hotel:, id: method.id, purpose: :guest_advance)

    expect(result).to be_success
    expect(result.payment_method).to eq(method)
  end

  it "rejects a guest-advance method used for a direct collection" do
    result = described_class.call(hotel:, id: method_for(:guest_advance).id, purpose: :direct)

    expect(result).not_to be_success
    expect(result.error).to eq("Select a valid direct payment method.")
    expect(result.payment_method).to be_nil
  end

  it "rejects a direct method used for a guest advance" do
    result = described_class.call(hotel:, id: method_for(:direct).id, purpose: :guest_advance)

    expect(result).not_to be_success
    expect(result.error).to eq("Select a valid guest advance payment method.")
  end

  it "rejects a blank, unknown, inactive, or other hotel's method" do
    other_hotel_method = create(:hotel_payment_method, hotel: create(:hotel), guest_advance: true)
    inactive = method_for(:guest_advance)
    inactive.transaction_code.update!(active: false)

    expect(described_class.call(hotel:, id: nil, purpose: :guest_advance)).not_to be_success
    expect(described_class.call(hotel:, id: -1, purpose: :guest_advance)).not_to be_success
    expect(described_class.call(hotel:, id: other_hotel_method.id, purpose: :guest_advance)).not_to be_success
    expect(described_class.call(hotel:, id: inactive.id, purpose: :guest_advance)).not_to be_success
  end

  it "rejects an unknown purpose" do
    result = described_class.call(hotel:, id: method_for(:direct).id, purpose: :refund)

    expect(result).not_to be_success
    expect(result.error).to eq("Unknown payment method purpose.")
  end
end
