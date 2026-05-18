# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::FolioTransactions", type: :request do
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
    post hotel_booking_folio_transactions_path(hotel, booking), params: { folio_transaction: params }
  end

  context "with post_folio_transactions permission" do
    before do
      grant_permission("post_folio_transactions")
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

      post_transaction(transaction_type: "payment", category: "cash", amount: "100.00", description: "Cash", posting_date: closed_date)

      expect(flash[:alert]).to include("business date #{closed_date} is already closed")
    end
  end

  it "requires post_folio_transactions permission" do
    folio

    expect {
      post_transaction(transaction_type: "payment", category: "cash", amount: "100.00", description: "Cash", posting_date: Date.current)
    }.not_to change(FolioTransaction, :count)

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq("You are not authorized to perform this action.")
  end

  it "redirects with an error when the booking has no folio" do
    grant_permission("post_folio_transactions")

    post_transaction(transaction_type: "payment", category: "cash", amount: "100.00", description: "Cash", posting_date: Date.current)

    expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    expect(flash[:alert]).to eq("Booking has no folio.")
  end
end
