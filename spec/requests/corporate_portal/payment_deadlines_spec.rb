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

    expected = booking.payment_due_at.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y, %-l.%M%P %Z")
    expect(response.parsed_body.text).to include(expected)
  end

  it "shows the deadline on the bookings list" do
    agent_booking

    get corporate_bookings_path

    expect(response.parsed_body.text).to include("Pay MYR 500.00")
  end

  # Checking the guest in takes the rooms out of the sweeper's reach, and used to
  # take the debt off the agent's screen with them: the row vanished from the
  # list and the booking page called itself paid, right up until the desk hit an
  # open folio at checkout.
  describe "once the guest has checked in unpaid" do
    def checked_in_booking
      agent_booking(payment_due_at: 1.hour.ago)
        .tap { |booking| booking.transition_status_to!("checked_in", event: "check_in") }
    end

    it "keeps the booking on the agent's list, still asking to be paid" do
      checked_in_booking

      get corporate_bookings_path

      expect(response.parsed_body.text).to include("Pay MYR 500.00")
    end

    it "asks for settlement rather than reading as a missed deadline" do
      booking = checked_in_booking

      get corporate_booking_path(booking)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.text).to include("guest checked in, still unpaid")
      expect(response.parsed_body.text).to include("Settle this booking with the hotel before they check out")
      expect(response.parsed_body.text).not_to include("past its payment deadline")
    end

    it "still offers the pay-now action" do
      booking = checked_in_booking

      get corporate_booking_path(booking)

      expect(response.body).to include(new_corporate_ar_payment_submission_path(booking_id: booking.id))
    end
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

  # The deadline panel only renders while awaiting_payment?, so once a slip is
  # approved (or the booking closes) it disappears -- and with it, the only
  # other place the agent could see what they had sent was their one-time
  # submission confirmation page.
  describe "the slip stays visible on the booking regardless of its state" do
    it "shows a pending slip, with a link to view it" do
      booking = agent_booking
      submission = create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship,
                                                   booking: booking, reference_number: "TRF-VIEW")

      get corporate_booking_path(booking)

      expect(response.body).to include("TRF-VIEW")
      expect(response.body).to include(rails_blob_path(submission.slip, disposition: "inline"))
      expect(response.body).to include("Pending")
    end

    it "still shows an approved slip after the deadline panel has gone" do
      booking = agent_booking(payment_status: "captured", payment_due_at: nil)
      submission = create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship,
                                                   booking: booking, reference_number: "TRF-APPROVED",
                                                   status: "approved", reviewed_by: create(:user), reviewed_at: Time.current,
                                                   ar_payment: create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship))

      get corporate_booking_path(booking)

      expect(response.body).not_to include("Pay now")
      expect(response.body).to include("TRF-APPROVED")
      expect(response.body).to include("Approved")
      expect(response.body).to include(rails_blob_path(submission.slip, disposition: "inline"))
    end

    it "shows a rejected slip's reason alongside it" do
      booking = agent_booking
      submission = create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship,
                                                   booking: booking, reference_number: "TRF-REJECTED",
                                                   status: "rejected", rejection_reason: "Amount did not match",
                                                   reviewed_by: create(:user), reviewed_at: Time.current)

      get corporate_booking_path(booking)

      expect(response.body).to include("TRF-REJECTED")
      expect(response.body).to include("Rejected")
      expect(response.body).to include("Amount did not match")
      expect(response.body).to include(rails_blob_path(submission.slip, disposition: "inline"))
    end

    it "says nothing when nothing has been submitted yet" do
      booking = agent_booking

      get corporate_booking_path(booking)

      expect(response.body).not_to include("Payment slips")
    end
  end
end
