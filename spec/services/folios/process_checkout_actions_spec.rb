# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::ProcessCheckoutActions do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", currency: "MYR") }
  let(:user) { create(:user, :superadmin) }
  let(:company_relationship) { create(:hotel_corporate_account, hotel: hotel, direct_bill_enabled: true) }
  let!(:guest_folio) { create(:booking_folio, booking: booking, hotel: hotel) }
  let!(:company_folio) { create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: company_relationship) }
  let(:posting_date) { Date.current }

  before do
    allow(Folios::BookingCheckoutReadiness).to receive(:call).and_return(
      OpenStruct.new(blockers: [], ready?: true)
    )
  end

  def call_service(actions, actor: user)
    described_class.call(
      booking: booking,
      hotel: hotel,
      user: actor,
      action_params: actions,
      posting_date: posting_date
    )
  end

  it "requires an action for every folio" do
    result = call_service({ guest_folio.id.to_s => { action: "close" } })

    expect(result).not_to be_success
    expect(result.error).to eq("Company Folio: checkout action is required.")
  end

  it "requires the payment amount to match the projected balance" do
    create(:folio_transaction, booking_folio: guest_folio, amount: 100)

    result = call_service({
      guest_folio.id.to_s => { action: "pay_now", amount: "90.00", payment_method: "cash" },
      company_folio.id.to_s => { action: "close" }
    })

    expect(result.error).to eq("Guest Folio: payment amount must equal MYR 100.00.")
  end

  it "rejects unsupported payment methods" do
    create(:folio_transaction, booking_folio: guest_folio, amount: 100)

    result = call_service({
      guest_folio.id.to_s => { action: "pay_now", amount: "100.00", payment_method: "crypto" },
      company_folio.id.to_s => { action: "close" }
    })

    expect(result.error).to eq("Guest Folio: payment method is not supported.")
  end

  it "requires payment posting permission" do
    create(:folio_transaction, booking_folio: guest_folio, amount: 100)

    result = call_service(
      {
        guest_folio.id.to_s => { action: "pay_now", amount: "100.00", payment_method: "cash" },
        company_folio.id.to_s => { action: "close" }
      },
      actor: create(:user)
    )

    expect(result.error).to eq("You do not have permission to post checkout payments.")
  end

  it "posts an approved checkout payment" do
    create(:folio_transaction, booking_folio: guest_folio, amount: 100)
    posted = OpenStruct.new(success?: true)
    allow(Folios::PostStaffTransaction).to receive(:call).and_return(posted)

    result = call_service({
      guest_folio.id.to_s => { action: "pay_now", amount: "100.00", payment_method: "cash", payment_reference: "RCPT-1" },
      company_folio.id.to_s => { action: "close" }
    })

    expect(result).to be_success
    expect(Folios::PostStaffTransaction).to have_received(:call).with(
      hash_including(
        folio: guest_folio,
        transaction_type: "payment",
        amount: 100.to_d,
        posting_date: posting_date
      )
    )
  end

  it "requires a reason for checkout exceptions" do
    create(:folio_transaction, booking_folio: company_folio, amount: 100)

    result = call_service({
      guest_folio.id.to_s => { action: "close" },
      company_folio.id.to_s => { action: "keep_open" }
    })

    expect(result.error).to eq("Company Folio: reason is required for keep open.")
  end

  it "rejects keep open for Company & Government folios without direct bill enabled" do
    company_relationship.update!(direct_bill_enabled: false)
    create(:folio_transaction, booking_folio: company_folio, amount: 100)

    result = call_service({
      guest_folio.id.to_s => { action: "close" },
      company_folio.id.to_s => { action: "keep_open", reason: "No direct bill" }
    })

    expect(result.error).to eq("Company Folio: Keep open is not allowed.")
  end

  it "keeps legacy unlinked company folios eligible for keep open" do
    company_folio.update_columns(hotel_corporate_account_id: nil)
    create(:folio_transaction, booking_folio: company_folio, amount: 100)

    expect {
      @result = call_service({
        guest_folio.id.to_s => { action: "close" },
        company_folio.id.to_s => { action: "keep_open", reason: "Legacy direct billing" }
      })
    }.to change(FolioOperationLog.where(operation_type: "checkout_exception"), :count).by(1)

    expect(@result).to be_success
  end

  it "records an approved checkout exception" do
    create(:folio_transaction, booking_folio: company_folio, amount: 100)

    expect {
      @result = call_service({
        guest_folio.id.to_s => { action: "close" },
        company_folio.id.to_s => { action: "keep_open", reason: "Direct billing approved" }
      })
    }.to change(FolioOperationLog.where(operation_type: "checkout_exception"), :count).by(1)

    expect(@result).to be_success
    expect(@result.exception_folio_ids).to eq([ company_folio.id ])
    expect(FolioOperationLog.last).to have_attributes(
      source_folio: company_folio,
      reason: "Direct billing approved"
    )
    expect(FolioOperationLog.last.metadata["checkout_action"]).to eq("keep_open")
  end
end
