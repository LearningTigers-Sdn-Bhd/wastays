# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CorporatePortal payment deadlines", type: :request do
  let(:user) { create(:user, :corporate) }
  let(:hotel) { create(:hotel, status: "live", agent_payment_hold_hours: 48) }
  let(:relationship) do
    create(:hotel_corporate_account, corporate_account: user.account, hotel: hotel, account_type: "travel_agent")
  end

  before do
    relationship
    sign_in_as(user)
    user.account.hotel_corporate_accounts.reload
  end

  def agent_booking(overrides = {})
    create(:booking, {
      hotel: hotel,
      hotel_corporate_account: relationship,
      status: "confirmed",
      payment_status: "pending",
      payment_due_at: 2.days.from_now,
      total_amount: 500,
      currency: "MYR"
    }.merge(overrides))
  end

  it "shows the deadline and a pay-now action on the booking" do
    booking = agent_booking

    get corporate_booking_path(booking)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Pay now")
    expect(response.parsed_body.text).to include("Pay MYR 500.00")
    expect(response.body).to include(new_corporate_ar_payment_submission_path(booking_id: booking.id))
  end

  it "states the deadline in the hotel's timezone, named" do
    booking = agent_booking

    get corporate_booking_path(booking)

    expected = booking.payment_due_at.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y, %H:%M %Z")
    expect(response.parsed_body.text).to include(expected)
  end

  it "shows the deadline on the bookings list" do
    agent_booking

    get corporate_bookings_path

    expect(response.parsed_body.text).to include("Pay MYR 500.00")
  end

  it "says nothing about payment on a booking that has none due" do
    agent_booking(payment_due_at: nil)

    get corporate_bookings_path

    expect(response.body).not_to include("Pay now")
  end

  describe "submitting a transfer for a booking" do
    it "records the submission against the booking and pauses the clock" do
      booking = agent_booking

      expect {
        post corporate_ar_payment_submissions_path, params: {
          ar_payment_submission: {
            booking_id: booking.id,
            reference_number: "TRF-900",
            received_at: Date.current,
            payment_method: "bank_transfer",
            slip: fixture_file_upload("spec/fixtures/files/sample_image.jpg", "image/jpeg")
          }
        }
      }.to change(ArPaymentSubmission, :count).by(1)

      submission = ArPaymentSubmission.last
      expect(submission.booking).to eq(booking)
      expect(submission.amount).to eq(booking.total_amount)
      expect(submission).to be_pending
      expect(response).to redirect_to(corporate_booking_path(booking))
    end

    it "shows the paused state instead of pay-now while it is under review" do
      booking = agent_booking
      create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking)

      get corporate_booking_path(booking)

      expect(response.body).to include("Slip under review")
      expect(response.body).not_to include("Pay now")
    end

    it "refuses a booking belonging to another account" do
      other = create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent")
      booking = create(:booking, hotel: hotel, hotel_corporate_account: other,
                                 status: "confirmed", payment_status: "pending",
                                 payment_due_at: 2.days.from_now)

      expect {
        post corporate_ar_payment_submissions_path, params: {
          ar_payment_submission: {
            booking_id: booking.id,
            reference_number: "TRF-901",
            received_at: Date.current,
            payment_method: "bank_transfer",
            slip: fixture_file_upload("spec/fixtures/files/sample_image.jpg", "image/jpeg")
          }
        }
      }.not_to change(ArPaymentSubmission, :count)

      expect(response).to redirect_to(corporate_bookings_path)
    end
  end
end
