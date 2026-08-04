require "rails_helper"

RSpec.describe Folios::Payments::PostConfiguredSurcharge do
  let(:folio) { create(:booking_folio) }
  let(:hotel) { folio.hotel }
  let(:user) do
    user = create(:user, account: hotel.account)
    permission = Permission.find_or_create_by!(slug: "post_folio_charges") { |record| record.name = "Post Folio Charges" }
    role = create(:role, account: hotel.account, permissions: [ permission ])
    create(:user_hotel_access, user:, hotel:, role:)
    user
  end

  def payment_method(extra_charge: nil, **attributes)
    PaymentMethods::EnsureDefaults.call(hotel)
    method = hotel.hotel_payment_methods.active.find_by!(guest_advance: true)
    method.update!(surcharge_extra_charge: extra_charge, **attributes) if attributes.any?
    method
  end

  it "posts nothing when the method carries no surcharge" do
    result = described_class.call(
      folio:, payment_method: payment_method, base_amount: 200, user:, operation_key: "spec:no-surcharge"
    )

    expect(result).to be_success
    expect(result).to have_attributes(transactions: [], surcharge_amount: 0.to_d, surcharge_tax_total: 0.to_d)
    expect(folio.folio_transactions.count).to eq(0)
  end

  it "posts a fixed surcharge charge against the configured extra charge code" do
    extra_charge = create(:hotel_extra_charge, hotel:)
    method = payment_method(extra_charge:, surcharge_posting_type: "fixed", surcharge_value: 5)

    result = described_class.call(
      folio:, payment_method: method, base_amount: 200, user:, operation_key: "spec:fixed",
      metadata: { source: "spec" }
    )

    expect(result).to be_success
    expect(result.surcharge_amount).to eq(5.to_d)
    posted = folio.folio_transactions.sole
    expect(posted).to have_attributes(
      amount: 5.to_d, transaction_type: "charge", transaction_code: extra_charge.transaction_code
    )
    expect(posted.description).to eq("#{method.name} surcharge fee")
    expect(posted.metadata).to include(
      "posting_source" => "payment_surcharge",
      "source" => "spec",
      "hotel_extra_charge_id" => extra_charge.id,
      "hotel_payment_method_id" => method.id,
      "payment_surcharge_amount" => "5.0"
    )
  end

  it "reports the tax posted on a percentage surcharge" do
    hotel.update!(sst_enabled: true)
    extra_charge = create(:hotel_extra_charge, hotel:)
    extra_charge.transaction_code.update!(is_taxable: true)
    extra_charge.transaction_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
    method = payment_method(extra_charge:, surcharge_posting_type: "percentage", surcharge_value: 2)

    result = described_class.call(
      folio:, payment_method: method, base_amount: 200, user:, operation_key: "spec:percentage"
    )

    expect(result).to be_success
    # 2% of 200 = 4.00, taxed at 8% SST = 0.32.
    expect(result).to have_attributes(surcharge_amount: 4.to_d, surcharge_tax_total: 0.32.to_d)
    expect(result.tax_transactions.sum { |transaction| transaction.amount.to_d }).to eq(0.32.to_d)
    expect(result.transactions.size).to eq(2)
  end

  it "fails when the configured surcharge charge is inactive" do
    extra_charge = create(:hotel_extra_charge, hotel:)
    method = payment_method(extra_charge:, surcharge_posting_type: "fixed", surcharge_value: 5)
    extra_charge.transaction_code.update!(active: false)

    result = described_class.call(
      folio:, payment_method: method, base_amount: 200, user:, operation_key: "spec:inactive"
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Payment surcharge is not available.")
    expect(folio.folio_transactions.count).to eq(0)
  end

  it "applies night-audit override options for a backdated posting" do
    extra_charge = create(:hotel_extra_charge, hotel:)
    method = payment_method(extra_charge:, surcharge_posting_type: "fixed", surcharge_value: 5)

    result = described_class.call(
      folio:, payment_method: method, base_amount: 200, user:, operation_key: "spec:backdated",
      override_night_audit: true, override_reason: "Router was down"
    )

    expect(result).to be_success
    expect(result.surcharge_amount).to eq(5.to_d)
  end
end
