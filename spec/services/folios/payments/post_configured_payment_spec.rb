require "rails_helper"

RSpec.describe Folios::Payments::PostConfiguredPayment do
  let(:folio) { create(:booking_folio) }
  let(:hotel) { folio.hotel }
  let(:user) { create(:user, :superadmin) }

  it "posts the selected method without a surcharge" do
    PaymentMethods::EnsureDefaults.call(hotel)
    method = hotel.hotel_payment_methods.joins(:transaction_code).find_by!(transaction_codes: { system_key: "cash_payment" })

    result = described_class.call(
      folio: folio, user: user, payment_method_id: method.id, base_amount: 100,
      description: "Cash payment"
    )

    expect(result.success?).to be(true)
    expect(result.transaction).to have_attributes(amount: 100.to_d, category: "cash", transaction_code: method.transaction_code)
    expect(result.transaction.metadata).to include(
      "hotel_payment_method_id" => method.id,
      "payment_base_amount" => "100.0",
      "payment_collected_total" => "100.0"
    )
  end

  it "posts a taxable surcharge and collects the complete total" do
    tax = create(:hotel_tax, hotel: hotel, name: "Service Tax", rate_type: "percentage", amount: 6, enabled: true)
    extra_charge = create(:hotel_extra_charge, hotel: hotel)
    extra_charge.transaction_code.update!(is_taxable: true)
    extra_charge.transaction_code.taxes = [ tax ]
    code = hotel.transaction_codes.create!(system_key: "terminal_payment", code: "TERM", name: "Terminal", kind: "payment", category: "gateway_payment")
    method = hotel.hotel_payment_methods.create!(
      transaction_code: code,
      payment_method_type: "bank_gateway",
      surcharge_posting_type: "percentage",
      surcharge_value: 2,
      surcharge_extra_charge: extra_charge
    )

    result = described_class.call(
      folio: folio, user: user, payment_method_id: method.id, base_amount: 100,
      description: "Terminal payment"
    )

    expect(result.success?).to be(true)
    surcharge, surcharge_tax, payment = result.transactions
    expect(surcharge).to have_attributes(transaction_type: "charge", amount: 2.to_d, transaction_code: extra_charge.transaction_code)
    expect(surcharge_tax).to have_attributes(transaction_type: "charge", category: "tax", amount: 0.12.to_d)
    expect(payment).to have_attributes(transaction_type: "payment", amount: 102.12.to_d, transaction_code: code)
    expect(folio.reload.outstanding_balance).to eq(-100.to_d)
    expect(result.transactions.map(&:operation_key).uniq.size).to eq(1)
  end

  it "rejects a method belonging to another hotel" do
    foreign_method = create(:hotel_payment_method)

    expect {
      result = described_class.call(
        folio: folio, user: user, payment_method_id: foreign_method.id, base_amount: 100,
        description: "Forged payment"
      )
      expect(result.error).to eq("Payment method is not valid.")
    }.not_to change(FolioTransaction, :count)
  end
end
