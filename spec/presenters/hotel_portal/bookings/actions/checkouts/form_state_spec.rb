# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Bookings::Actions::Checkouts::FormState do
  let(:folio_class) { Struct.new(:id) }
  let(:row_class) { Struct.new(:folio, :default_action, :balance) }
  let(:booking_class) { Struct.new(:id) }
  let(:sheet_class) { Struct.new(:folio_rows) }
  let(:anchor) { booking_class.new(10) }
  let(:sibling) { booking_class.new(20) }
  let(:anchor_row) { row_class.new(folio_class.new(101), "pay_now", 50.to_d) }
  let(:sibling_row) { row_class.new(folio_class.new(202), "direct_bill", 75.to_d) }
  let(:sheets) { { anchor => sheet_class.new([ anchor_row ]), sibling => sheet_class.new([ sibling_row ]) } }

  def build_state(params: {}, submitted: false, group: true)
    described_class.new(
      anchor_booking: anchor,
      bookings: [ anchor, sibling ],
      sheets: sheets,
      checked_out_at_default: "2026-07-22T11:00",
      params: params,
      submitted: submitted,
      group: group
    )
  end

  it "builds GET defaults from the anchor booking and folio presenters" do
    state = build_state

    expect(state.selected_booking_ids).to eq([ "10", "20" ])
    expect(state.checked_out_at).to eq("2026-07-22T11:00")
    expect(state.folio_values(anchor, anchor_row)).to include(
      action: "pay_now",
      amount: "50.00",
      payment_method: "cash",
      payment_reference: nil,
      reason: nil
    )
    expect(state.early_departure_values(anchor)).to include(apply_charge: "false", type: "amount", charge_amount: "0.00")
    expect(state.release_security_deposit?).to be(true)
  end

  it "selects only the anchor booking on a non-group GET" do
    expect(build_state(group: false).selected_booking_ids).to eq([ "10" ])
  end

  it "preserves submitted values, including intentional blanks" do
    state = build_state(
      submitted: true,
      params: {
        booking_ids: [ sibling.id ],
        booking: { checked_out_at: "" },
        checkout_bookings: {
          sibling.id => {
            folios: {
              sibling_row.folio.id => {
                action: "keep_open",
                amount: "75.00",
                payment_method: "bank_transfer",
                payment_reference: "",
                reason: "Awaiting approval"
              }
            }
          }
        },
        early_departures: {
          sibling.id => { apply_charge: "true", type: "percentage", value: "25", charge_amount: "18.75" }
        },
        release_security_deposit: "0",
        security_deposit_release_method: "card",
        security_deposit_release_reference: ""
      }
    )

    expect(state.selected_booking_ids).to eq([ "20" ])
    expect(state.checked_out_at).to eq("")
    expect(state.folio_values(sibling, sibling_row)).to include(
      action: "keep_open",
      payment_method: "bank_transfer",
      payment_reference: "",
      reason: "Awaiting approval"
    )
    expect(state.early_departure_values(sibling)).to include(
      apply_charge: "true",
      type: "percentage",
      value: "25",
      charge_amount: "18.75"
    )
    expect(state.release_security_deposit?).to be(false)
    expect(state.security_deposit_release_method).to eq("card")
    expect(state.security_deposit_release_reference).to eq("")
  end

  it "calculates summaries from the selected bookings and submitted actions" do
    state = build_state(
      submitted: true,
      params: {
        booking_ids: [ anchor.id, sibling.id ],
        checkout_bookings: {
          anchor.id => { folios: { anchor_row.folio.id => { action: "pay_now", amount: "55.25" } } },
          sibling.id => { folios: { sibling_row.folio.id => { action: "manager_review", amount: "75.00" } } }
        }
      }
    )

    expect(state.collect_now_total).to eq(55.25.to_d)
    expect(state.direct_bill_total).to be_zero
    expect(state.keep_open_count).to eq(1)
  end
end
