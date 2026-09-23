require "rails_helper"

RSpec.describe "Public::Concierge::Stays", type: :request do
  let(:feature_group) { create(:feature_group) }
  let(:ai_concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true, plan: plan) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", guest_name: "Ahmad Zulkifli") }
  let(:stay_access) { create(:concierge_stay_access, hotel: hotel, booking: booking) }
  let(:code) { booking.confirmation_token }

  before do
    create(:plan_feature, plan: plan, feature: ai_concierge_page_feature, enabled: true)
    stay_access
  end

  # The status column guards its own transitions, so a spec names the event that
  # moves the booking.
  def move_booking(status, event, **attributes)
    booking.status_transition_event = event
    booking.update!(status: status, **attributes)
  end

  def stay_url(id = stay_access.stay_access_id)
    concierge_stay_path(hotel.unique_id, hotel.public_id, id)
  end

  def verify_url(id = stay_access.stay_access_id)
    concierge_stay_verification_path(hotel.unique_id, hotel.public_id, id)
  end

  def open_the_stay(id = stay_access.stay_access_id)
    post verify_url(id), params: { confirmation_token: code }
  end

  describe "GET the stay page without a session" do
    it "shows the locked page at the same URL" do
      get stay_url

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Booking confirmation code")
    end

    it "keeps the stay private on the locked page" do
      booking.booking_rooms.first&.update!(room_number: "1201")

      get stay_url

      expect(response.body).not_to include("Ahmad Zulkifli")
      expect(response.body).not_to include("1201")
      expect(response.body).not_to include("Checked in")
    end

    it "shows the unavailable page for an unknown link" do
      get stay_url("ZZZZZZZZZZZZ")

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("not")
    end

    it "shows the unavailable page for a revoked link" do
      Concierge::StayAccess::Revoke.new(booking: booking).call

      get stay_url

      expect(response).to have_http_status(:not_found)
    end

    it "shows the unavailable page after the grace period" do
      move_booking("completed", "check_out", checked_out_at: 8.days.ago)

      get stay_url

      expect(response).to have_http_status(:not_found)
    end

    it "does not show a stay page for a link of the wrong shape" do
      get "/concierge/#{hotel.unique_id}/#{hotel.public_id}/stay/short"

      expect(response.body).not_to include("Booking confirmation code")
      expect(response.body).not_to include("Your Stay")
    end
  end

  describe "POST the confirmation code" do
    it "redirects to the same stable stay URL" do
      open_the_stay

      expect(response).to redirect_to(stay_url)
    end

    it "sets a stay-session cookie that the URL does not carry" do
      open_the_stay

      expect(response.cookies["concierge_stay"]).to be_present
      expect(response.headers["Location"]).not_to include(response.cookies["concierge_stay"])
    end

    it "shows the stay page after verification" do
      open_the_stay
      get stay_url

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Your Stay")
    end

    it "does not ask for the code again while the session is valid" do
      open_the_stay
      get stay_url

      expect(response.body).not_to include(%(name="confirmation_token"))
    end

    it "shows the locked page again after a wrong code" do
      post verify_url, params: { confirmation_token: "WS-WRONG" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(Concierge::StayAccess::VerifyDevice::GENERIC_ERROR)
      expect(response.cookies["concierge_stay"]).to be_blank
    end

    it "refuses a code for a revoked link" do
      Concierge::StayAccess::Revoke.new(booking: booking).call

      open_the_stay

      expect(response).to have_http_status(:not_found)
      expect(response.cookies["concierge_stay"]).to be_blank
    end
  end

  describe "session limits" do
    it "refuses a session that belongs to another hotel" do
      open_the_stay
      other_hotel = create(:hotel, status: "live", concierge_enabled: true, plan: plan)
      other_booking = create(:booking, hotel: other_hotel, status: "checked_in")
      other_access = create(:concierge_stay_access, hotel: other_hotel, booking: other_booking)

      get concierge_stay_path(other_hotel.unique_id, other_hotel.public_id, other_access.stay_access_id)

      expect(response.body).to include("Booking confirmation code")
    end

    it "shows the locked page for a second stay at the same hotel" do
      open_the_stay
      second_booking = create(:booking, hotel: hotel, status: "checked_in")
      second_access = create(:concierge_stay_access, hotel: hotel, booking: second_booking)

      get stay_url(second_access.stay_access_id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Booking confirmation code")
    end

    it "ends the session when staff revokes the record" do
      open_the_stay
      Concierge::StayAccess::Revoke.new(booking: booking).call

      get stay_url

      expect(response).to have_http_status(:not_found)
    end

    it "ends the session when the booking reaches a terminal status" do
      open_the_stay
      move_booking("voided", "void")

      get stay_url

      expect(response).to have_http_status(:not_found)
    end

    it "keeps the stay page open during the grace period" do
      open_the_stay
      move_booking("completed", "check_out", checked_out_at: 2.days.ago)

      get stay_url

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Your Stay")
    end
  end

  describe "POST the recovery request" do
    def recover_url(id = stay_access.stay_access_id)
      concierge_stay_recovery_path(hotel.unique_id, hotel.public_id, id)
    end

    it "queues the stay-link mail" do
      expect { post recover_url }.to have_enqueued_mail(GuestMailer, :stay_link)
    end

    it "gives one answer that does not say whether the mail went out" do
      post recover_url

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("a new link is on its way")
    end

    it "gives the same answer after the send cap" do
      4.times { post recover_url }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("a new link is on its way")
    end

    it "offers recovery on a locked page" do
      # The delay between wrong codes grows to 16 seconds, so the clock has to
      # move or the later posts get the wait message and never count.
      ConciergeStayAccess::MAX_ATTEMPTS.times do
        post verify_url, params: { confirmation_token: "WS-WRONG" }
        travel 20.seconds
      end

      get stay_url

      expect(response.body).to include("Email me a new link")
      expect(response.body).not_to include("Booking confirmation code")
    end

    it "refuses recovery for a revoked link" do
      Concierge::StayAccess::Revoke.new(booking: booking).call

      post recover_url

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "more than one device" do
    it "keeps the first browser open after a second one verifies" do
      open_the_stay

      # A second jar is a second browser. The record holds no device state, so
      # one verification cannot end another browser's session.
      second = ActionDispatch::Integration::Session.new(Rails.application)
      second.post verify_url, params: { confirmation_token: code }

      expect(second.response).to have_http_status(:found)
      expect(second.response.cookies["concierge_stay"]).to be_present

      get stay_url
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Your Stay")
    end

    it "gives the second browser the stay page too" do
      open_the_stay

      second = ActionDispatch::Integration::Session.new(Rails.application)
      second.post verify_url, params: { confirmation_token: code }
      second.get stay_url

      expect(second.response).to have_http_status(:ok)
      expect(second.response.body).to include("Your Stay")
    end
  end
end
