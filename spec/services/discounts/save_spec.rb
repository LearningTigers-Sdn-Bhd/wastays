require "rails_helper"

RSpec.describe Discounts::Save do
  let(:hotel) { create(:hotel) }

  def new_discount
    HotelDiscount.new(hotel:, transaction_code: hotel.transaction_codes.build(hotel:))
  end

  def attributes(**overrides)
    {
      name: "Loyalty Rebate", code: "loyal rbt!", active: "1", description: "Repeat guests",
      pricing_type: "percentage", rate_value: "10", application_scope: "all_eligible_charges"
    }.merge(overrides)
  end

  it "creates the discount and its backing adjustment transaction code" do
    result = described_class.call(discount: new_discount, attributes: attributes)

    expect(result).to be_success
    discount = result.discount.reload
    expect(discount).to have_attributes(pricing_type: "percentage", rate_value: 10.to_d, application_scope: "all_eligible_charges")
    expect(discount.transaction_code).to have_attributes(
      name: "Loyalty Rebate", kind: "adjustment", category: "discount", is_taxable: false, system_required: false
    )
    # Codes are normalised to A-Z0-9 with single underscores.
    expect(discount.transaction_code.code).to eq("LOYAL_RBT")
    expect(discount.transaction_code.system_key).to eq("discount_loyal_rbt")
  end

  it "clears the rate and forces overrides on for a manual discount" do
    result = described_class.call(
      discount: new_discount, attributes: attributes(pricing_type: "manual", rate_value: "10", allow_amount_override: "0")
    )

    expect(result).to be_success
    expect(result.discount).to have_attributes(rate_value: nil, allow_amount_override: true)
  end

  it "only honours an override toggle for fixed pricing" do
    fixed = described_class.call(
      discount: new_discount, attributes: attributes(code: "FIXED", pricing_type: "fixed", rate_value: "20", allow_amount_override: "1")
    )
    percentage = described_class.call(
      discount: new_discount, attributes: attributes(code: "PCT", allow_amount_override: "1")
    )

    expect(fixed.discount.allow_amount_override).to be(true)
    expect(percentage.discount.allow_amount_override).to be(false)
  end

  it "links selected charge codes and drops them when the scope changes" do
    charge = create(:transaction_code, hotel:, kind: "charge")
    discount = new_discount

    selected = described_class.call(discount:, attributes: attributes(
      application_scope: "selected_charges", applicable_transaction_code_ids: [ "", charge.id.to_s ]
    ))
    expect(selected).to be_success
    expect(selected.discount.applicable_transaction_codes).to contain_exactly(charge)

    widened = described_class.call(discount: discount.reload, attributes: attributes(application_scope: "room_charges"))
    expect(widened).to be_success
    expect(widened.discount.reload.applicable_transaction_codes).to be_empty
  end

  it "rejects a charge code that is not an available charge at this hotel" do
    foreign = create(:transaction_code, hotel: create(:hotel), kind: "charge")

    result = described_class.call(discount: new_discount, attributes: attributes(
      application_scope: "selected_charges", applicable_transaction_code_ids: [ foreign.id.to_s ]
    ))

    expect(result).not_to be_success
    expect(result.error).to include("include an unavailable charge code")
  end

  it "rolls back and surfaces transaction-code errors when the code is blank" do
    expect {
      @result = described_class.call(discount: new_discount, attributes: attributes(code: ""))
    }.not_to change(HotelDiscount, :count)

    expect(@result).not_to be_success
    expect(@result.error).to be_present
  end

  it "suffixes the system key when one is already taken at the hotel" do
    create(:transaction_code, hotel:, system_key: "discount_loyal_rbt")

    result = described_class.call(discount: new_discount, attributes: attributes)

    expect(result).to be_success
    expect(result.discount.transaction_code.system_key).to eq("discount_loyal_rbt_2")
  end
end
