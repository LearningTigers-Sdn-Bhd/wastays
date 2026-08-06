require "rails_helper"

RSpec.describe Deposits::ConfiguredPrepayment do
  let(:folio) { create(:booking_folio) }
  let(:booking) { folio.booking }
  let(:hotel) { folio.hotel }

  def guest_advance_method
    PaymentMethods::EnsureDefaults.call(hotel)
    hotel.hotel_payment_methods.active.find_by!(guest_advance: true)
  end

  def call(**overrides)
    described_class.call(**{
      owner: booking, folios: [ folio ], base_amount: 200, payment_method_id: guest_advance_method.id,
      actor: nil, operation_key: "spec:#{SecureRandom.hex(4)}"
    }.merge(overrides))
  end

  it "records one prepayment deposit and applies it to the folio" do
    result = call(external_reference: "REF-1")

    expect(result).to be_success
    expect(result.collected_total).to eq(200.to_d)
    expect(result.deposit).to have_attributes(kind: "prepayment", amount: 200.to_d, external_reference: "REF-1")
    expect(result.deposit.metadata).to include(
      "source" => "configured_booking_prepayment",
      "payment_base_amount" => "200.0",
      "payment_collected_total" => "200.0"
    )
    expect(result.movements).to be_present
  end

  it "collects the surcharge on top of the base amount" do
    method = guest_advance_method
    method.update!(surcharge_posting_type: "fixed", surcharge_value: 6, surcharge_extra_charge: create(:hotel_extra_charge, hotel:))

    result = call(payment_method_id: method.id)

    expect(result).to be_success
    expect(result.collected_total).to eq(206.to_d)
    expect(result.deposit.amount).to eq(206.to_d)
    expect(result.deposit.metadata).to include("payment_surcharge_amount" => "6.0", "payment_base_amount" => "200.0")
  end

  it "splits one group deposit across the member folios by booking total" do
    group = create(:group_booking, hotel:)
    first = create(:booking, hotel:, group_booking: group, total_amount: 200)
    second = create(:booking, hotel:, group_booking: group, total_amount: 600)
    folios = [ first, second ].map { |member| create(:booking_folio, booking: member) }

    result = call(owner: group, folios:, base_amount: 800)

    expect(result).to be_success
    expect(result.deposit.amount).to eq(800.to_d)
    applied = result.deposit.deposit_movements.movement_type_apply
    expect(applied.sum(:amount)).to eq(800.to_d)
    expect(applied.map { |movement| movement.amount.to_d }).to contain_exactly(200.to_d, 600.to_d)
  end

  it "rejects a non-positive amount and a folio-less application" do
    expect(call(base_amount: 0).error).to eq("Payment amount must be greater than 0.")
    expect(call(folios: []).error).to eq("Payment cannot be applied without a folio.")
  end

  it "rejects a direct payment method and records nothing" do
    PaymentMethods::EnsureDefaults.call(hotel)
    direct = hotel.hotel_payment_methods.active.find_by!(guest_advance: false)

    expect { @result = call(payment_method_id: direct.id) }.not_to change(Deposit, :count)
    expect(@result).not_to be_success
    expect(@result.error).to eq("Select a valid guest advance payment method.")
  end

  it "returns the same deposit when replayed with the same operation key" do
    operation_key = "spec:replay"

    first = call(operation_key:)
    expect { @second = call(operation_key:) }.not_to change(Deposit, :count)
    expect(@second.deposit).to eq(first.deposit)
  end
end
