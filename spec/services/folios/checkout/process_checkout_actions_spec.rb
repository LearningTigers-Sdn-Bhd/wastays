# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Checkout::ProcessCheckoutActions do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", currency: "MYR") }
  let(:user) { create(:user, :superadmin) }
  let(:company_relationship) { create(:hotel_corporate_account, :direct_bill, hotel: hotel) }
  let!(:guest_folio) { create(:booking_folio, booking: booking, hotel: hotel) }
  let!(:company_folio) { create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: company_relationship) }
  let(:posting_date) { Date.current }

  before do
    allow(Folios::Checkout::BookingCheckoutReadiness).to receive(:call).and_return(
      Folios::Checkout::BookingCheckoutReadiness::Report.new("ready?": true, blockers: [], folios: [], projected_balance: 0.to_d)
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
    expect(result.error).to eq("#{company_folio.display_name}: checkout action is required.")
  end

  it "requires the payment amount to match the projected balance" do
    create(:folio_transaction, booking_folio: guest_folio, amount: 100)

    result = call_service({
      guest_folio.id.to_s => { action: "pay_now", amount: "90.00", payment_method: "cash" },
      company_folio.id.to_s => { action: "close" }
    })

    expect(result.error).to eq("#{guest_folio.display_name}: payment amount must equal MYR 100.00.")
  end

  it "rejects unsupported payment methods" do
    create(:folio_transaction, booking_folio: guest_folio, amount: 100)

    result = call_service({
      guest_folio.id.to_s => { action: "pay_now", amount: "100.00", payment_method: "crypto" },
      company_folio.id.to_s => { action: "close" }
    })

    expect(result.error).to eq("#{guest_folio.display_name}: payment method is not supported.")
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
    posted = Folios::Transactions::TransactionResult.success(transaction: nil)
    allow(Folios::Transactions::PostStaffTransaction).to receive(:call).and_return(posted)

    result = call_service({
      guest_folio.id.to_s => { action: "pay_now", amount: "100.00", payment_method: "cash", payment_reference: "RCPT-1" },
      company_folio.id.to_s => { action: "close" }
    })

    expect(result).to be_success
    expect(Folios::Transactions::PostStaffTransaction).to have_received(:call).with(
      hash_including(
        folio: guest_folio,
        transaction_type: "payment",
        amount: 100.to_d,
        posting_date: posting_date
      )
    )
  end

  {
    "cash" => "cash",
    "card" => "card",
    "bank_transfer" => "bank",
    "manual" => "gateway"
  }.each do |method, payment_source|
    it "posts #{method} checkout payments through the #{payment_source} payment source" do
      create(:folio_transaction, booking_folio: guest_folio, amount: 100)
      allow(Folios::Transactions::PostStaffTransaction).to receive(:call).and_return(Folios::Transactions::TransactionResult.success(transaction: nil))

      result = call_service({
        guest_folio.id.to_s => { action: "pay_now", amount: "100.00", payment_method: method, payment_reference: "REF-1" },
        company_folio.id.to_s => { action: "close" }
      })

      expect(result).to be_success
      expect(Folios::Transactions::PostStaffTransaction).to have_received(:call).with(
        hash_including(options: hash_including(payment_source: payment_source))
      )
    end
  end

  it "requires a reason for checkout exceptions" do
    create(:folio_transaction, booking_folio: company_folio, amount: 100)

    result = call_service({
      guest_folio.id.to_s => { action: "close" },
      company_folio.id.to_s => { action: "keep_open" }
    })

    expect(result.error).to eq("#{company_folio.display_name}: reason is required for keep open.")
  end

  it "allows keeping Corporate Account folios open without Direct Bill enabled" do
    company_relationship.update!(relationship_type: "standard")
    create(:folio_transaction, booking_folio: company_folio, amount: 100)

    expect {
      @result = call_service({
        guest_folio.id.to_s => { action: "close" },
        company_folio.id.to_s => { action: "keep_open", reason: "No direct bill" }
      })
    }.to change(FolioOperationLog.where(operation_type: "checkout_exception"), :count).by(1)

    expect(@result).to be_success
    expect(@result.exception_folio_ids).to eq([ company_folio.id ])
  end

  it "keeps unlinked Corporate Account folios open when Direct Bill is not available" do
    company_folio.update_columns(hotel_corporate_account_id: nil)
    create(:folio_transaction, booking_folio: company_folio, amount: 100)

    expect {
      @result = call_service({
        guest_folio.id.to_s => { action: "close" },
        company_folio.id.to_s => { action: "keep_open", reason: "Missing direct billing" }
      })
    }.to change(FolioOperationLog.where(operation_type: "checkout_exception"), :count).by(1)

    expect(@result).to be_success
    expect(@result.exception_folio_ids).to eq([ company_folio.id ])
  end

  it "accepts Direct Bill for eligible Corporate Account folios" do
    create(:folio_transaction, booking_folio: company_folio, amount: 100)

    result = call_service({
      guest_folio.id.to_s => { action: "close" },
      company_folio.id.to_s => { action: "direct_bill", amount: "100.00" }
    })

    expect(result).to be_success
    expect(result.direct_bill_folio_ids).to eq([ company_folio.id ])
    expect(result.exception_folio_ids).to eq([])
  end

  it "blocks Direct Bill above the credit limit unless an authorized override has a reason" do
    company_relationship.update!(credit_limit: 50, credit_currency: "MYR")
    create(:folio_transaction, booking_folio: company_folio, amount: 100)
    actions = {
      guest_folio.id.to_s => { action: "close" },
      company_folio.id.to_s => { action: "direct_bill", amount: "100.00" }
    }

    blocked = call_service(actions)
    overridden = call_service(actions.deep_merge(company_folio.id.to_s => {
      credit_override: "1", credit_override_reason: "Approved by finance"
    }))

    expect(blocked.error).to include("credit limit exceeded")
    expect(overridden).to be_success
  end

  it "does not accept a credit override from an unauthorized user" do
    company_relationship.update!(credit_limit: 50, credit_currency: "MYR")
    create(:folio_transaction, booking_folio: company_folio, amount: 100)

    result = call_service({
      guest_folio.id.to_s => { action: "close" },
      company_folio.id.to_s => {
        action: "direct_bill", amount: "100.00", credit_override: "1", credit_override_reason: "Approved"
      }
    }, actor: create(:user))

    expect(result.error).to include("do not have permission")
  end


  it "checks the combined Direct Bill amount for folios on the same account" do
    company_relationship.update!(credit_limit: 100, credit_currency: "MYR")
    second_company_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel,
      hotel_corporate_account: company_relationship)
    create(:folio_transaction, booking_folio: company_folio, amount: 60)
    create(:folio_transaction, booking_folio: second_company_folio, amount: 60)

    result = call_service({
      guest_folio.id.to_s => { action: "close" },
      company_folio.id.to_s => { action: "direct_bill", amount: "60.00" },
      second_company_folio.id.to_s => { action: "direct_bill", amount: "60.00" }
    })

    expect(result.error).to include("credit limit exceeded")
  end

  it "rejects Direct Bill when the Corporate Account is not eligible" do
    company_relationship.update!(relationship_type: "standard")
    create(:folio_transaction, booking_folio: company_folio, amount: 100)

    result = call_service({
      guest_folio.id.to_s => { action: "close" },
      company_folio.id.to_s => { action: "direct_bill", amount: "100.00" }
    })

    expect(result.error).to eq("#{company_folio.display_name}: Direct bill is not allowed.")
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
