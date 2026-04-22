require "rails_helper"
require "securerandom"

RSpec.describe "Admin::OnboardingTracker", type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:admin_account) { create(:account, name: "Admin Tracker #{token}") }
  let(:superadmin) { create(:user, :superadmin, account: admin_account) }

  before do
    sign_in_as(superadmin)
  end

  describe "GET /admin/hotels/onboarding" do
    let!(:hotel) do
      create(
        :hotel,
        account: admin_account,
        name: "Luma Stay #{token}",
        city: "Kuala Lumpur",
        status: "pending_review",
        onboarding_start_date: Date.new(2026, 4, 15),
        onboarding_end_date: Date.new(2026, 4, 20)
      )
    end
    let!(:training_session_one) do
      OnboardingSession.create!(
        hotel: hotel,
        trainer_name: "Mira Tan",
        status: "scheduled",
        scheduled_at: Time.zone.local(2026, 4, 24, 9, 0),
        meeting_link: "https://meet.example.com/session-one",
        notes: "TRAINING_SESSION"
      )
    end
    let!(:training_session_two) do
      OnboardingSession.create!(
        hotel: hotel,
        trainer_name: "Farid Osman",
        status: "scheduled",
        scheduled_at: Time.zone.local(2026, 4, 26, 14, 30),
        meeting_link: "https://meet.example.com/session-two",
        notes: "TRAINING_SESSION"
      )
    end

    let!(:short_onboarding_hotel) do
      create(
        :hotel,
        account: admin_account,
        name: "Short Stay #{token}",
        city: "Johor Bahru",
        status: "pending_review",
        onboarding_start_date: Date.new(2026, 4, 20),
        onboarding_end_date: Date.new(2026, 4, 22)
      )
    end

    let!(:long_onboarding_hotel) do
      create(
        :hotel,
        account: admin_account,
        name: "Long Stay #{token}",
        city: "Penang",
        status: "pending_review",
        onboarding_start_date: Date.new(2026, 4, 10),
        onboarding_end_date: Date.new(2026, 4, 22)
      )
    end

    it "renders the tracker filters and formatted scheduled sessions" do
      get onboarding_admin_hotels_path(format: :html)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="onboarding-tracker-filter"')
      expect(response.body).to include('placeholder="Type hotel, city, or trainer name..."')
      expect(response.body).to include("From date")
      expect(response.body).to include("To date")
      expect(response.body).to include("Clear")

      # Should show both sessions formatted in the user's timezone (Kuala Lumpur)
      # Time.zone.local(2026, 4, 24, 9, 0) in UTC is 24 Apr 2026, 05:00 PM in KL
      # Time.zone.local(2026, 4, 26, 14, 30) in UTC is 26 Apr 2026, 10:30 PM in KL
      expect(response.body).to include("24 Apr 2026, 05:00 PM")
      expect(response.body).to include("26 Apr 2026, 10:30 PM")
      expect(response.body).to include("Mira Tan")
      expect(response.body).to include("Farid Osman")
      expect(response.body).to include('data-search-text="Luma Stay')
      expect(response.body).to include('data-scheduled-dates="2026-04-24|2026-04-26"')
    end

    it "sorts hotels from the shortest onboarding period to the longest" do
      get onboarding_admin_hotels_path

      expect(response).to have_http_status(:ok)

      # Use Nokogiri to get the hotel names in the order they appear in the table rows
      doc = Nokogiri::HTML(response.body)
      hotel_names = doc.css('[data-onboarding-tracker-filter-target="row"] td:first-child').map(&:text).map(&:strip)

      # Expected order (by duration_days):
      # Short Stay (2 days), Luma Stay (5 days), Long Stay (12 days)
      expect(hotel_names.any? { |n| n.include?("Short Stay") }).to be true
      expect(hotel_names.any? { |n| n.include?("Luma Stay") }).to be true
      expect(hotel_names.any? { |n| n.include?("Long Stay") }).to be true

      short_idx = hotel_names.index { |n| n.include?("Short Stay") }
      luma_idx = hotel_names.index { |n| n.include?("Luma Stay") }
      long_idx = hotel_names.index { |n| n.include?("Long Stay") }

      expect(short_idx).to be < luma_idx
      expect(luma_idx).to be < long_idx
    end
  end
end
