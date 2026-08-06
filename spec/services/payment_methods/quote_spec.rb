require "rails_helper"

RSpec.describe PaymentMethods::Quote do
  let(:hotel) { create(:hotel) }

  def guest_advance_method
    PaymentMethods::EnsureDefaults.call(hotel)
    hotel.hotel_payment_methods.active.find_by!(guest_advance: true)
  end

  it "quotes a surcharge-free method at its base amount" do
    result = described_class.call(hotel:, payment_method_id: guest_advance_method.id, base_amount: "200.00")

    expect(result).to be_success
    expect(result).to have_attributes(
      base_amount: 200.to_d, surcharge_amount: 0.to_d, surcharge_tax_total: 0.to_d, collected_total: 200.to_d
    )
  end

  it "adds a fixed surcharge to the collected total" do
    method = guest_advance_method
    method.update!(surcharge_posting_type: "fixed", surcharge_value: 3, surcharge_extra_charge: create(:hotel_extra_charge, hotel:))

    result = described_class.call(hotel:, payment_method_id: method.id, base_amount: "200.00")

    expect(result).to be_success
    expect(result).to have_attributes(surcharge_amount: 3.to_d, collected_total: 203.to_d)
  end

  it "adds a percentage surcharge and its tax to the collected total" do
    hotel.update!(sst_enabled: true)
    extra_charge = create(:hotel_extra_charge, hotel:)
    extra_charge.transaction_code.update!(is_taxable: true)
    extra_charge.transaction_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
    method = guest_advance_method
    method.update!(surcharge_posting_type: "percentage", surcharge_value: 2, surcharge_extra_charge: extra_charge)

    result = described_class.call(hotel:, payment_method_id: method.id, base_amount: "200.00")

    expect(result).to be_success
    # 2% of 200 = 4.00, plus 8% SST on the surcharge = 0.32.
    expect(result).to have_attributes(surcharge_amount: 4.to_d, surcharge_tax_total: 0.32.to_d, collected_total: 204.32.to_d)
  end

  it "fails when the method is not eligible for the requested purpose" do
    result = described_class.call(hotel:, payment_method_id: guest_advance_method.id, base_amount: "200.00", purpose: :direct)

    expect(result).not_to be_success
    expect(result.error).to eq("Select a valid direct payment method.")
  end

  it "fails when the surcharge charge is missing or inactive" do
    extra_charge = create(:hotel_extra_charge, hotel:)
    method = guest_advance_method
    method.update!(surcharge_posting_type: "fixed", surcharge_value: 3, surcharge_extra_charge: extra_charge)
    extra_charge.transaction_code.update!(active: false)

    result = described_class.call(hotel:, payment_method_id: method.id, base_amount: "200.00")

    expect(result).not_to be_success
    expect(result.error).to eq("Payment surcharge is not available.")
  end
end
