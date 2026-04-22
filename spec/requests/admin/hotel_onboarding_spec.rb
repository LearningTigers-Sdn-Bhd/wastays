require "rails_helper"
require "securerandom"

RSpec.describe "Admin::HotelOnboarding", type: :request do
  include ActionView::RecordIdentifier

  let(:token) { SecureRandom.hex(6) }
  let(:admin_account) { create(:account, name: "Admin Account #{token}") }
  let(:superadmin) { create(:user, :superadmin, account: admin_account) }

  before do
    sign_in_as(superadmin)
  end

  describe "GET /admin/hotels/:id/onboarding" do
    let(:hotel) do
      create(
        :hotel,
        account: admin_account,
        name: "Onboarding Hotel #{token}",
        city: "Kuala Lumpur",
        status: "pending_review"
      )
    end

    let!(:earlier_session) do
      OnboardingSession.create!(
        hotel: hotel,
        trainer_name: "Mira Tan",
        status: "scheduled",
        scheduled_at: Time.zone.local(2026, 4, 24, 9, 0),
        meeting_link: "https://meet.example.com/earlier",
        notes: "TRAINING_SESSION"
      )
    end

    let!(:later_session) do
      OnboardingSession.create!(
        hotel: hotel,
        trainer_name: "Farid Osman",
        status: "scheduled",
        scheduled_at: Time.zone.local(2026, 4, 26, 14, 30),
        meeting_link: "https://meet.example.com/later",
        notes: "TRAINING_SESSION"
      )
    end

    it "lists training sessions in increasing date and time order" do
      get onboarding_admin_hotel_path(hotel)

      expect(response).to have_http_status(:ok)

      doc = Nokogiri::HTML(response.body)
      trainer_names = doc.css('#onboarding_sessions_list p.font-bold').map(&:text).map(&:strip)

      # Should show Mira Tan (Earlier) then Farid Osman (Later)
      expect(trainer_names).to include("Mira Tan")
      expect(trainer_names).to include("Farid Osman")
      expect(trainer_names.index("Mira Tan")).to be < trainer_names.index("Farid Osman")
    end
  end

  describe "PATCH /admin/hotels/:id/onboarding-sessions/:session_id" do
    let(:hotel) do
      create(
        :hotel,
        account: admin_account,
        name: "Sort Test #{token}",
        city: "Kuala Lumpur",
        status: "pending_review"
      )
    end

    let!(:first_session) do
      OnboardingSession.create!(
        hotel: hotel,
        trainer_name: "Alpha Trainer",
        status: "scheduled",
        scheduled_at: Time.zone.local(2026, 4, 24, 9, 0),
        meeting_link: "https://meet.example.com/alpha",
        notes: "TRAINING_SESSION"
      )
    end

    let!(:second_session) do
      OnboardingSession.create!(
        hotel: hotel,
        trainer_name: "Beta Trainer",
        status: "scheduled",
        scheduled_at: Time.zone.local(2026, 4, 26, 9, 0),
        meeting_link: "https://meet.example.com/beta",
        notes: "TRAINING_SESSION"
      )
    end

    it "returns a turbo stream update after editing a session" do
      patch update_onboarding_session_admin_hotel_path(hotel, session_id: second_session.id),
            params: {
              trainer_name: "Beta Trainer",
              scheduled_at: "2026-04-23T09:00",
              meeting_link: "https://meet.example.com/beta"
            },
            headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('turbo-stream action="replace" target="onboarding_sessions_list"')

      # After update, second_session (now Apr 23) should come before first_session (Apr 24)
      template_content = response.body.match(/<template>(.*)<\/template>/m)[1]
      doc = Nokogiri::HTML(template_content)
      times = doc.css('p.text-xs.text-slate-500').map(&:text).map(&:strip)

      # Filter for only strings that start with "Scheduled:"
      scheduled_times = times.select { |t| t.start_with?("Scheduled:") }

      # The updated session at Apr 23 should be first
      expect(scheduled_times[0]).to include("23 Apr 2026")
      expect(scheduled_times[1]).to include("24 Apr 2026")
    end
  end

  describe "DELETE /admin/hotels/:id/onboarding-sessions/:session_id" do
    let(:hotel) do
      create(
        :hotel,
        account: admin_account,
        name: "Delete Test #{token}",
        city: "Kuala Lumpur",
        status: "pending_review"
      )
    end

    let!(:session) do
      OnboardingSession.create!(
        hotel: hotel,
        trainer_name: "Delete Me",
        status: "scheduled",
        scheduled_at: Time.zone.local(2026, 4, 24, 9, 0),
        meeting_link: "https://meet.example.com/delete",
        notes: "TRAINING_SESSION"
      )
    end

    it "deletes the onboarding session and returns to the updated list" do
      expect do
        delete destroy_onboarding_session_admin_hotel_path(hotel, session_id: session.id),
               headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
      end.to change(OnboardingSession, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('turbo-stream action="replace" target="onboarding_sessions_list"')
      expect(response.body).not_to include("Delete Me")
    end
  end

  describe "GET /admin/hotels/:id/onboarding with completed sessions" do
    let(:hotel) do
      create(
        :hotel,
        account: admin_account,
        name: "Completed Delete Guard #{token}",
        city: "Kuala Lumpur",
        status: "pending_review"
      )
    end

    let!(:completed_session) do
      OnboardingSession.create!(
        hotel: hotel,
        trainer_name: "Completed Trainer",
        status: "completed",
        scheduled_at: Time.zone.local(2026, 4, 24, 9, 0),
        completed_at: Time.zone.local(2026, 4, 24, 10, 0),
        meeting_link: "https://meet.example.com/completed",
        notes: "TRAINING_SESSION"
      )
    end

    it "does not show delete for completed sessions" do
      get onboarding_admin_hotel_path(hotel)

      expect(response).to have_http_status(:ok)

      doc = Nokogiri::HTML(response.body)
      session_row = doc.at_css("#" + dom_id(completed_session))
      expect(session_row.text).to include("Completed Trainer")
      expect(session_row.text).not_to include("Delete")
    end
  end
end
