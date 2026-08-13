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
      get onboarding_admin_hotel_path(hotel, format: :html)

      expect(response).to have_http_status(:ok)

      doc = Nokogiri::HTML(response.body)
      trainer_names = doc.css('#onboarding_sessions_list p.font-bold').map(&:text).map(&:strip)

      # Should show Mira Tan (Earlier) then Farid Osman (Later)
      expect(trainer_names).to include("Mira Tan")
      expect(trainer_names).to include("Farid Osman")
      expect(trainer_names.index("Mira Tan")).to be < trainer_names.index("Farid Osman")
    end

    it "shows the submitted snapshot, safe OTA presence, deliveries, and review actions" do
      submitter = create(:user, account: hotel.account, name: "Property Owner")
      sections = Onboarding::SectionCatalog.keys.index_with { { "state" => "complete", "decision" => {} } }
      submission = create(
        :onboarding_submission,
        hotel:,
        submitted_by: submitter,
        snapshot: {
          "property" => { "name" => hotel.name, "city" => hotel.city, "country" => hotel.country, "default_currency" => "MYR" },
          "sections" => sections,
          "rooms" => [ { "name" => "Deluxe", "quantity" => 4 } ],
          "rates" => { "coverage" => { "configured_percentage" => "100.0", "end_date" => "2027-08-12" } },
          "commercial" => { "payment_methods" => [ { "name" => "Cash" } ] },
          "ota_handover" => [ { "channel_name" => "Booking.com", "credentials_supplied" => true } ]
        }
      )
      create(:onboarding_delivery, onboarding_submission: submission, status: "failed")

      get onboarding_admin_hotel_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Property Owner", "Deluxe", "Booking.com", "Credentials supplied", "Request changes", "Approve &amp; go live")
      expect(response.body).not_to include("private-user", "private-password")
      document = Nokogiri::HTML(response.body)
      expect(document.css('input[name="section_keys[]"]').size).to eq(12)
      expect(document.at_css('#request-onboarding-changes-sheet')).to be_present
    end
  end

  describe "POST review actions" do
    let(:hotel) { create(:hotel, account: admin_account, status: "pending_review") }

    it "passes targeted sections and the explanation to the change service" do
      result = Onboarding::RequestChanges::Result.success(submission: nil, section_keys: %w[rooms])
      allow(Onboarding::RequestChanges).to receive(:call).and_return(result)

      post request_onboarding_changes_admin_hotel_path(hotel),
           params: { section_keys: %w[rooms], explanation: "Add the missing room." }

      expect(Onboarding::RequestChanges).to have_received(:call).with(
        hotel:, actor: superadmin, section_keys: %w[rooms], explanation: "Add the missing room."
      )
      expect(response).to redirect_to(onboarding_admin_hotel_path(hotel))
    end

    it "uses only the canonical approval service" do
      result = Onboarding::ApproveOnboarding::Result.failure("Not ready", submission: nil, readiness: nil)
      allow(Onboarding::ApproveOnboarding).to receive(:call).and_return(result)

      post approve_onboarding_admin_hotel_path(hotel)

      expect(Onboarding::ApproveOnboarding).to have_received(:call).with(hotel:, actor: superadmin)
      expect(response).to redirect_to(onboarding_admin_hotel_path(hotel))
      expect(flash[:alert]).to eq("Not ready")
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
      patch admin_hotel_onboarding_session_path(hotel, second_session),
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
      times = doc.css('p.text-xs.text-muted-foreground').map(&:text).map(&:strip)

      # Filter for only strings that start with "Scheduled:"
      scheduled_times = times.select { |t| t.start_with?("Scheduled:") }

      # The updated session at Apr 23 should be first
      expect(scheduled_times[0]).to include("23 Apr 2026")
      expect(scheduled_times[1]).to include("24 Apr 2026")
    end
  end

  describe "POST /admin/hotels/:id/onboarding-sessions" do
    let(:hotel) do
      create(
        :hotel,
        account: admin_account,
        name: "Create Reset #{token}",
        city: "Kuala Lumpur",
        status: "pending_review"
      )
    end

    it "resets the add session form after a successful save" do
      post admin_hotel_onboarding_sessions_path(hotel),
           params: {
             trainer_name: "New Trainer",
             scheduled_at: "2026-04-24T09:00",
             meeting_link: "https://meet.example.com/new"
           },
           headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('turbo-stream action="replace" target="new_onboarding_session_form"')
      expect(response.body).to include('value=""')
      expect(OnboardingSession.where(hotel: hotel).count).to eq(1)
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
        delete admin_hotel_onboarding_session_path(hotel, session),
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
      get onboarding_admin_hotel_path(hotel, format: :html)

      expect(response).to have_http_status(:ok)

      doc = Nokogiri::HTML(response.body)
      session_row = doc.at_css("#" + dom_id(completed_session))
      expect(session_row.text).to include("Completed Trainer")
      expect(session_row.text).not_to include("Delete")
    end
  end
end
