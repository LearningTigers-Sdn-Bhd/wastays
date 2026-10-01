# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal agent payments panel", type: :request do
  let(:hotel) { create(:hotel, status: "live", agent_payment_hold_hours: 72) }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent") }
  let(:booking) do
    create(:booking, hotel: hotel, hotel_corporate_account: relationship, status: "confirmed", payment_status: "pending",
                     total_amount: 1000, currency: "MYR", check_in: 60.days.from_now, check_out: 62.days.from_now)
  end
  let!(:folio) { create(:booking_folio, booking: booking, hotel: hotel, currency: "MYR") }
  let(:deposit) { booking.payment_instalments.find_by!(kind: "deposit") }
  let(:balance) { booking.payment_instalments.find_by!(kind: "balance") }
  let(:tab_path) { hotel_booking_workspace_path(hotel, booking, tab: "agent_payments") }

  def grant(*slugs)
    slugs.each do |slug|
      role.permissions << Permission.find_or_create_by!(slug: slug) { |permission| permission.name = slug.titleize }
    end
  end

  before do
    grant("manage_bookings", "view_bookings")
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    Bookings::CreatePaymentSchedule.call(booking: booking)
    sign_in_as(user)
  end

  describe "the tab" do
    it "shows the schedule with each stage, its amount and its state" do
      get tab_path

      expect(response).to have_http_status(:success)
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("#agent-payments-heading").text).to eq("Agent payments")
      rows = doc.css("#agent-payments-#{booking.id} tbody tr").map { |row| row.css("td").map { |cell| cell.text.squish } }
      expect(rows.map { |row| row.first(2) }).to eq([ [ "Deposit", "MYR 500.00" ], [ "Balance", "MYR 500.00" ] ])
      expect(rows.map { |row| row[3] }).to all(include("Owed"))
    end

    it "is listed in the workspace tabs for an agent booking" do
      get hotel_booking_workspace_path(hotel, booking, tab: "booking_details")

      expect(response.body).to include("Deposits") # the tab strip rendered
      expect(response.body).to include("tab=agent_payments")
    end

    it "is absent for a booking with no payment schedule" do
      plain = create(:booking, hotel: hotel)

      get hotel_booking_workspace_path(hotel, plain, tab: "booking_details")

      expect(response.body).to include("Deposits") # the tab strip rendered
      expect(response.body).not_to include("tab=agent_payments")
    end

    it "offers only the actions the user's permissions allow" do
      get tab_path
      expect(response.body).not_to include("Mark paid")

      grant("post_folio_payments")
      get tab_path
      expect(response.body).to include("Mark paid")
      expect(response.body).not_to include(">Refund<")
    end

    it "offers Mark paid on the deposit only, while it is owed" do
      grant("post_folio_payments")

      get tab_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("#agent-instalment-#{deposit.id}").text).to include("Mark paid")
      expect(doc.at_css("#agent-instalment-#{balance.id}").text).not_to include("Mark paid")
    end
  end

  describe "POST mark_agent_instalment_paid" do
    def mark(instalment, **params)
      post mark_agent_instalment_paid_hotel_booking_workspace_path(hotel, booking), params: {
        instalment_id: instalment.id, payment_method: "cash", reference: "RCPT-9"
      }.merge(params)
    end

    it "posts the payment to the folio and marks the stage paid" do
      grant("post_folio_payments")

      mark(deposit)

      expect(response).to redirect_to(tab_path)
      expect(flash[:notice]).to eq("Payment recorded.")
      expect(deposit.reload.status).to eq("paid")
      expect(folio.folio_transactions.payment.sum(:amount)).to eq(500)
    end

    it "is refused without the permission to post payments" do
      mark(deposit)

      expect(response).not_to redirect_to(tab_path)
      expect(deposit.reload.status).to eq("pending")
      expect(folio.folio_transactions.count).to eq(0)
    end

    it "explains why when the stage cannot be marked paid" do
      grant("post_folio_payments")

      mark(balance)

      expect(response).to redirect_to(tab_path)
      expect(flash[:alert]).to eq("Record the earlier stage first.")
    end

    it "cannot reach another hotel's instalment" do
      grant("post_folio_payments")
      other = create(:booking, hotel: create(:hotel, status: "live"), total_amount: 400, currency: "MYR")
      other_instalment = other.payment_instalments.create!(position: 1, kind: "full", amount: 400, due_at: 2.days.from_now)

      mark(other_instalment)

      expect(other_instalment.reload.status).to eq("pending")
    end
  end

  describe "POST refund_agent_instalment" do
    before do
      grant("post_folio_payments")
      post mark_agent_instalment_paid_hotel_booking_workspace_path(hotel, booking), params: {
        instalment_id: deposit.id, payment_method: "cash", reference: "RCPT-1"
      }
    end

    def refund(**params)
      post refund_agent_instalment_hotel_booking_workspace_path(hotel, booking), params: {
        instalment_id: deposit.id, refund_source: "cash", reason: "Paid twice"
      }.merge(params)
    end

    it "is refused without the permission to execute refunds, and posts nothing" do
      expect { refund }.not_to change { folio.folio_transactions.count }

      expect(deposit.reload.status).to eq("paid")
    end

    it "refunds the stage and records why" do
      grant("execute_folio_refunds")

      refund

      expect(response).to redirect_to(tab_path)
      expect(flash[:notice]).to eq("Refund recorded.")
      expect(deposit.reload).to have_attributes(status: "refunded", refund_reason: "Paid twice", refunded_by_id: user.id)
    end

    it "needs a reason" do
      grant("execute_folio_refunds")

      refund(reason: "")

      expect(flash[:alert]).to eq("Say why it is being refunded.")
      expect(deposit.reload.status).to eq("paid")
    end
  end

  describe "POST reopen_agent_instalment" do
    before do
      grant("post_folio_payments", "execute_folio_refunds")
      post mark_agent_instalment_paid_hotel_booking_workspace_path(hotel, booking), params: {
        instalment_id: deposit.id, payment_method: "cash", reference: "RCPT-1"
      }
      post refund_agent_instalment_hotel_booking_workspace_path(hotel, booking), params: {
        instalment_id: deposit.id, refund_source: "cash", reason: "Hotel error"
      }
    end

    def reopen(**params)
      post reopen_agent_instalment_hotel_booking_workspace_path(hotel, booking), params: {
        instalment_id: deposit.id, due_on: 5.days.from_now.to_date.iso8601
      }.merge(params)
    end

    it "is refused without the permission to manage agent payments" do
      reopen

      expect(deposit.reload.status).to eq("refunded")
    end

    it "puts the stage back on the agent until the end of the chosen day, in the hotel's zone" do
      grant("manage_ar_payments")

      reopen

      expect(flash[:notice]).to eq("Payment reopened.")
      expect(deposit.reload.status).to eq("pending")
      due = deposit.due_at.in_time_zone(hotel.hotel_time_zone)
      expect([ due.hour, due.min ]).to eq([ 23, 59 ])
      expect(due.to_date).to eq(5.days.from_now.in_time_zone(hotel.hotel_time_zone).to_date)
    end

    it "refuses a date that is not usable" do
      grant("manage_ar_payments")

      reopen(due_on: "not a date")

      expect(flash[:alert]).to eq("Choose a deadline in the future.")
      expect(deposit.reload.status).to eq("refunded")
    end
  end
end
