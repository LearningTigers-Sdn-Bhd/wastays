# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::FolioTransactions", type: :request do
  around { |example| travel_to(Time.zone.local(2026, 6, 10, 3, 0, 0)) { example.run } }

  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in") }
  let(:folio) { create(:booking_folio, hotel: hotel, booking: booking, status: "open") }

  before do
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  def grant_permission(slug)
    permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    role.permissions << permission unless role.permissions.exists?(permission.id)
  end

  def post_transaction(params)
    post hotel_folio_transactions_path(hotel, booking), params: { folio_transaction: params }
  end

  def reverse_transaction(transaction, params)
    post reverse_hotel_folio_transaction_path(hotel, booking, transaction), params: { folio_transaction: params }
  end

  context "with granular folio permissions" do
    before do
      %w[
        post_folio_charges
        post_folio_payments
        execute_folio_refunds
        post_folio_adjustments
        post_folio_corrections
        post_folio_write_offs
      ].each { |slug| grant_permission(slug) }
      folio
    end

    it "posts a cash payment" do
      expect {
        post_transaction(transaction_type: "payment", category: "cash", amount: "100.00", description: "Cash payment", posting_date: Date.current)
      }.to change { folio.folio_transactions.payment.count }.by(1)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(folio.folio_transactions.last.category).to eq("cash")
    end

    it "posts an other charge" do
      expect {
        post_transaction(transaction_type: "charge", category: "other", amount: "25.00", description: "Lost key", posting_date: Date.current)
      }.to change { folio.folio_transactions.charge.count }.by(1)

      expect(folio.folio_transactions.last.category).to eq("other")
    end

    it "records a refund as a negative payment" do
      post_transaction(transaction_type: "payment", category: "refund", amount: "50.00", description: "Refund", posting_date: Date.current)

      transaction = folio.folio_transactions.payment.last
      expect(transaction.category).to eq("refund")
      expect(transaction.amount).to eq(-50.0)
    end

    it "posts a write-off adjustment" do
      expect {
        post_transaction(transaction_type: "adjustment", category: "write_off", amount: "50.00", description: "Manager write-off", posting_date: Date.current)
      }.to change { folio.folio_transactions.adjustment.count }.by(1)

      expect(folio.folio_transactions.last.category).to eq("write_off")
    end

    it "rejects disallowed manual charge categories" do
      expect {
        post_transaction(transaction_type: "charge", category: "tax", amount: "10.00", description: "Tax", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:alert]).to eq("Category is not allowed for charge transactions.")
    end

    it "rejects closed folios" do
      folio.update!(status: "closed")

      expect {
        post_transaction(transaction_type: "payment", category: "cash", amount: "100.00", description: "Cash", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(flash[:alert]).to include("Folio is closed")
    end

    it "rejects closed business dates" do
      closed_date = 1.day.ago.to_date
      create(:night_audit, hotel: hotel, business_date: closed_date, status: "completed")
      create(:hotel_business_date, hotel: hotel, business_date: closed_date, status: "closed")

      post_transaction(transaction_type: "payment", category: "cash", amount: "100.00", description: "Cash", posting_date: closed_date)

      expect(flash[:alert]).to include("business date #{closed_date} is already closed")
    end

    it "reverses a folio transaction with correction details" do
      transaction = create(:folio_transaction, booking_folio: folio, amount: 100, category: "accommodation")

      expect {
        reverse_transaction(transaction, correction_reason: "Posting error", correction_note: "Wrong booking", posting_date: Date.current)
      }.to change { folio.folio_transactions.adjustment.count }.by(1)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:notice]).to eq("Folio transaction reversed.")
      reversal = folio.folio_transactions.order(:id).last
      expect(reversal.reversal_of_transaction).to eq(transaction)
      expect(reversal.amount).to eq(-100.to_d)
      expect(transaction.reload.voided_by_transaction).to eq(reversal)
    end

    it "rejects reversal without a correction reason" do
      transaction = create(:folio_transaction, booking_folio: folio)

      expect {
        reverse_transaction(transaction, correction_reason: "", correction_note: "Wrong booking", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(flash[:alert]).to eq("Correction reason can't be blank.")
    end

    it "rejects reversal without a correction note" do
      transaction = create(:folio_transaction, booking_folio: folio)

      expect {
        reverse_transaction(transaction, correction_reason: "Posting error", correction_note: "", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(flash[:alert]).to eq("Correction note can't be blank.")
    end

    it "rejects already reversed transactions" do
      transaction = create(:folio_transaction, booking_folio: folio)
      result = Folios::ReverseTransaction.call(
        transaction: transaction,
        user: user,
        correction_reason: "Posting error",
        correction_note: "Initial correction"
      )
      expect(result).to be_success

      expect {
        reverse_transaction(transaction, correction_reason: "Posting error", correction_note: "Duplicate correction", posting_date: Date.current)
      }.not_to change(FolioTransaction, :count)

      expect(flash[:alert]).to eq("Transaction has already been reversed.")
    end
  end

  it "requires the matching granular permission to post" do
    folio

    expect {
      post_transaction(transaction_type: "payment", category: "cash", amount: "100.00", description: "Cash", posting_date: Date.current)
    }.not_to change(FolioTransaction, :count)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to include("permission")
  end

  it "does not allow the legacy post_folio_transactions permission to post" do
    grant_permission("post_folio_transactions")
    folio

    expect {
      post_transaction(transaction_type: "payment", category: "cash", amount: "100.00", description: "Cash", posting_date: Date.current)
    }.not_to change(FolioTransaction, :count)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to include("permission")
  end

  it "requires post_folio_corrections permission to reverse" do
    folio
    transaction = create(:folio_transaction, booking_folio: folio)

    expect {
      reverse_transaction(transaction, correction_reason: "Posting error", correction_note: "Wrong booking", posting_date: Date.current)
    }.not_to change(FolioTransaction, :count)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to include("permission")
  end

  it "requires execute_folio_refunds permission for manual refunds" do
    grant_permission("post_folio_payments")
    folio

    expect {
      post_transaction(transaction_type: "payment", category: "refund", amount: "50.00", description: "Refund", posting_date: Date.current)
    }.not_to change(FolioTransaction, :count)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to include("permission")
  end

  it "requires post_folio_write_offs permission for write-offs" do
    grant_permission("post_folio_adjustments")
    folio

    expect {
      post_transaction(transaction_type: "adjustment", category: "write_off", amount: "50.00", description: "Write-off", posting_date: Date.current)
    }.not_to change(FolioTransaction, :count)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to include("permission")
  end

  it "does not allow override_closed_folio params to bypass closed folio controls" do
    grant_permission("post_folio_payments")
    folio.update!(status: "closed")

    expect {
      post hotel_folio_transactions_path(hotel, booking), params: {
        folio_transaction: {
          transaction_type: "payment",
          category: "cash",
          amount: "100.00",
          description: "Cash",
          posting_date: Date.current,
          override_closed_folio: "true"
        }
      }
    }.not_to change(FolioTransaction, :count)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to include("Folio is closed")
  end

  it "does not allow override_night_audit params to bypass closed-date reversal controls" do
    grant_permission("post_folio_corrections")
    transaction = create(:folio_transaction, booking_folio: folio)
    closed_date = 1.day.ago.to_date
    create(:night_audit, hotel: hotel, business_date: closed_date, status: "completed")
    create(:hotel_business_date, hotel: hotel, business_date: closed_date, status: "closed")

    expect {
      reverse_transaction(
        transaction,
        correction_reason: "Posting error",
        correction_note: "Wrong booking",
        posting_date: closed_date,
        override_night_audit: "true"
      )
    }.not_to change(FolioTransaction, :count)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to include("override_financial_date_lock")
  end

  it "redirects with an error when the booking has no folio" do
    grant_permission("post_folio_payments")

    post_transaction(transaction_type: "payment", category: "cash", amount: "100.00", description: "Cash", posting_date: Date.current)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to eq("Booking has no folio.")
  end
end
