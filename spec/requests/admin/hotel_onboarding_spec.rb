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

    it "lists training sessions in increasing date and time order on the training tab" do
      get onboarding_tab_admin_hotel_path(hotel, tab: "training", format: :html)

      expect(response).to have_http_status(:ok)

      doc = Nokogiri::HTML(response.body)
      trainer_names = doc.css('#onboarding_sessions_list p.font-bold').map(&:text).map(&:strip)

      expect(doc.at_css("#admin-onboarding-tabs a[aria-current='page']").text.squish).to eq("Training")
      expect(response.body).to include("Training is managed separately")
      expect(response.body).not_to include("Setup review", "Onboarding history")
      expect(doc.css("table caption").map { |caption| caption.text.squish }).not_to include("Submitted property setup summary")
      expect(trainer_names).to include("Mira Tan")
      expect(trainer_names).to include("Farid Osman")
      expect(trainer_names.index("Mira Tan")).to be < trainer_names.index("Farid Osman")
    end

    it "shows the compact header and linked navigation with overview selected" do
      hotel.update!(
        onboarding_start_date: Date.new(2026, 4, 15),
        onboarding_end_date: Date.new(2026, 4, 20)
      )

      get onboarding_admin_hotel_path(hotel)

      document = Nokogiri::HTML(response.body)
      header = document.at_css('[data-testid="admin-onboarding-header"]')
      tabs = document.at_css("nav[aria-label='Onboarding review sections']")
      expect(response).to have_http_status(:ok)
      expect(header.at_css("a[href='#{admin_hotels_path(status: 'pending_review')}'][aria-label='Back to pending review']")).to be_present
      expect(header.at_css("h1").text).to eq(hotel.name)
      expect(header.text.squish).to include("Pending review", "Kuala Lumpur", "15 Apr – 20 Apr 2026 · 5 days")
      expect(header.at_css("#admin-onboarding-actions-trigger").text.squish).to eq("Actions")
      expect(header.at_css('button[command="show-modal"][commandfor="edit-onboarding-period-sheet"]').text.squish).to eq("Edit onboarding period")
      expect(tabs.css("a").map { |link| link.text.squish }).to eq([ "Overview", "History", "Training" ])
      expect(tabs.at_css("a[aria-current='page']").text.squish).to eq("Overview")
      expect(tabs.at_css("a[href='#{onboarding_admin_hotel_path(hotel)}']")).to be_present
      expect(document.at_css("#edit-onboarding-period-sheet")).to be_present
      expect(document.at_css("input[name='tab']")["value"]).to eq("overview")
      expect(document.at_css("input[name='start_date']")['value']).to eq("2026-04-15")
      expect(document.at_css("input[name='end_date']")['value']).to eq("2026-04-20")
      expect(document.at_css(".panel-alert").text).to include("No new onboarding submission")
      expect(document.at_css("table.panel-table")).to be_nil
    end

    it "shows the consolidated submitted setup workspace only on overview" do
      submitter = create(:user, account: hotel.account, name: "Property Owner")
      sections = Onboarding::SectionCatalog.keys.index_with { { "state" => "complete", "decision" => {} } }
      sections["staff_setup"] = { "state" => "skipped", "decision" => {} }
      sections.delete("channel_manager")
      submission = create(
        :onboarding_submission,
        hotel:,
        submitted_by: submitter,
        snapshot: {
          "property" => {
            "name" => hotel.name, "address" => "1 City Road", "city" => hotel.city, "country" => hotel.country,
            "default_currency" => "MYR", "sell_mode" => "per_room", "photo_count" => 5
          },
          "sections" => sections,
          "rooms" => [ { "name" => "Deluxe", "quantity" => 4 } ],
          "rates" => { "coverage" => { "configured_percentage" => "100.0", "end_date" => "2027-08-12", "complete" => true } },
          "commercial" => {
            "extra_charges" => [], "discounts" => [],
            "payment_methods" => [ { "name" => "Cash" } ], "corporate_accounts" => []
          },
          "ota_handover" => [ {
            "channel_name" => "Booking.com", "credentials_supplied" => true,
            "username" => "private-user", "password" => "private-password"
          } ]
        }
      )
      create(:onboarding_delivery, onboarding_submission: submission, delivery_type: "staff_invitation", status: "failed")
      create(:onboarding_delivery, onboarding_submission: submission, delivery_type: "corporate_invitation", status: "sent")
      allow(Rates::SetupCoverage).to receive(:call).and_call_original

      get onboarding_admin_hotel_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Property Owner", "Setup review", "Property submitted", "Deluxe", "Booking.com")
      expect(response.body).not_to include(
        "Onboarding history", "Training is managed separately", "private-user", "private-password"
      )
      document = Nokogiri::HTML(response.body)
      header = document.at_css('[data-testid="admin-onboarding-header"]')
      workspace = document.at_css("#admin-onboarding-overview")
      tab_content = document.at_css("[data-testid='admin-onboarding-tab-content']")
      table = workspace.css("table.panel-table").find do |candidate|
        candidate.at_css("caption").text.squish == "Submitted property setup summary"
      end
      metrics = document.css("section[aria-label='Submitted setup statistics'] .panel-metric-card")
      expect(header.text.squish).to include("Request changes", "Approve and go live")
      expect(document.at_css(".panel-page")["class"]).to include("panel-page--workspace")
      expect(tab_content["class"]).to include("min-h-0", "flex-1", "overflow-y-auto")
      expect(metrics.map { |metric| metric.text.squish }).to eq([
        "Required setup 7 of 7 Complete",
        "Optional decisions 4 of 5 1 deferred",
        "Rooms 4 1 room type",
        "Rate coverage 100% Through 12 Aug 2027"
      ])
      expect(workspace["class"]).to include("lg:grid-cols-2", "lg:items-start")
      expect(workspace.css("table.panel-table").size).to eq(5)
      expect(workspace.css("h2").map { |heading| heading.text.squish }).to eq([
        "Setup review", "Property submitted", "Rooms submitted", "Commercial setup", "Handover"
      ])
      expect(table.text.squish).to include(
        "Kuala Lumpur", "MYR", "1 room type · 4 rooms", "Coverage through 12 Aug 2027",
        "1 payment method", "1 channel handover"
      )
      expect(document.at_css(".panel-alert").text).to include("The property setup changed after submission")
      expect(table.at_css("caption").text.squish).to eq("Submitted property setup summary")
      expect(table["data-sticky-column"]).to eq("false")
      expect(table.css("thead th").map { |cell| cell.text.squish }).to eq([ "Section", "Submitted setup", "Status" ])
      expect(table.css("tbody th[scope='rowgroup']").map { |cell| cell.text.squish })
        .to eq([ "Property", "Team", "Finance", "Rooms & rates", "Commercial" ])
      expect(table.css("tbody th[scope='rowgroup']").map { |cell| cell.parent["class"] }.uniq).to eq([ "bg-muted/50" ])
      expect(table.css("tbody th[scope='row']").map { |cell| cell.text.squish }).to eq(
        Onboarding::SectionCatalog.keys.excluding("review").map do |key|
          HotelPortal::OnboardingPresenter::SECTION_CONTENT.fetch(key).first
        end
      )
      expect(table.css("tbody th[scope='row']").size).to eq(12)
      expect(table.css("a, button")).to be_empty
      expect(table.css(".panel-badge[data-variant='success']").size).to eq(10)
      expect(table.css(".panel-badge[data-variant='warning']").map { |badge| badge.text.squish }).to eq([ "Deferred" ])
      expect(table.css(".panel-badge[data-variant='neutral']").map { |badge| badge.text.squish }).to eq([ "Not started" ])
      table_rows = workspace.css("table.panel-table").to_h do |evidence_table|
        caption = evidence_table.at_css("caption").text.squish
        rows = evidence_table.css("tbody tr").map { |row| row.css("th, td").map { |cell| cell.text.squish } }
        [ caption, rows ]
      end
      expect(table_rows.fetch("Submitted property details")).to include([ "Address", "1 City Road" ], [ "Sell mode", "Per room" ], [ "Photos", "5" ])
      expect(table_rows.fetch("Submitted room types")).to include([ "Deluxe", "4" ])
      expect(table_rows.fetch("Submitted commercial setup")).to include([ "Extra charges", "0" ], [ "Payment methods", "1" ])
      expect(table_rows.fetch("Submitted handover details")).to include(
        [ "Invitation delivery", "1 sent · 0 held · 0 pending · 1 failed" ],
        [ "Booking.com", "Credentials supplied" ]
      )
      expect(document.css('input[name="section_keys[]"]').size).to eq(12)
      expect(document.at_css('#request-onboarding-changes-sheet')).to be_present
      expect(Rates::SetupCoverage).to have_received(:call).once
    end

    it "renders safe submitted-data fallbacks for an empty snapshot" do
      create(:onboarding_submission, hotel:, snapshot: { "sections" => {} })

      get onboarding_admin_hotel_path(hotel)

      document = Nokogiri::HTML(response.body)
      metric_text = document.css("section[aria-label='Submitted setup statistics'] .panel-metric-card").map { |metric| metric.text.squish }
      workspace = document.at_css("#admin-onboarding-overview")
      table_rows = workspace.css("table.panel-table").to_h do |evidence_table|
        caption = evidence_table.at_css("caption").text.squish
        rows = evidence_table.css("tbody tr").map { |row| row.css("th, td").map { |cell| cell.text.squish } }
        [ caption, rows ]
      end

      expect(response).to have_http_status(:ok)
      expect(metric_text).to eq([
        "Required setup 0 of 7 7 remaining",
        "Optional decisions 0 of 5 0 deferred",
        "Rooms 0 0 room types",
        "Rate coverage Not supplied No coverage date"
      ])
      expect(table_rows.fetch("Submitted property details")).to include([ "Name", "Not supplied" ], [ "Location", "Not supplied" ])
      expect(table_rows.fetch("Submitted room types")).to eq([ [ "No rooms submitted." ] ])
      expect(table_rows.fetch("Submitted commercial setup")).to include([ "Extra charges", "0" ])
      expect(table_rows.fetch("Submitted handover details")).to eq([
        [ "Invitation delivery", "No invitations created" ],
        [ "Channel handover", "No channels submitted" ]
      ])
    end

    it "does not route the removed submitted setup tab" do
      get "/admin/hotels/#{hotel.to_param}/onboarding/submitted-setup"

      expect(response).to have_http_status(:not_found)
    end

    it "shows audit events only on history without calculating readiness" do
      OnboardingAuditEvent.create!(
        hotel:,
        user: superadmin,
        event_type: "submitted",
        section_key: "rooms",
        occurred_at: Time.zone.local(2026, 4, 20, 12, 0)
      )
      allow(Rates::SetupCoverage).to receive(:call).and_call_original

      get onboarding_tab_admin_hotel_path(hotel, tab: "history")

      document = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(document.at_css("#admin-onboarding-tabs a[aria-current='page']").text.squish).to eq("History")
      expect(response.body).to include("Onboarding history", "Submitted", "Rooms")
      expect(response.body).not_to include("Setup review", "Training is managed separately")
      expect(document.at_css("#admin-onboarding-overview")).to be_nil
      expect(document.at_css("table.panel-table")).to be_nil
      expect(Rates::SetupCoverage).not_to have_received(:call)
    end

    it "does not route unknown onboarding tabs" do
      get "/admin/hotels/#{hotel.to_param}/onboarding/unknown"

      expect(response).to have_http_status(:not_found)
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

  describe "POST /admin/hotels/:id/save_onboarding_period" do
    let(:hotel) do
      create(
        :hotel,
        account: admin_account,
        status: "pending_review",
        onboarding_start_date: Date.new(2026, 4, 10),
        onboarding_end_date: Date.new(2026, 4, 12)
      )
    end

    it "updates a valid onboarding period" do
      post save_onboarding_period_admin_hotel_path(hotel),
           params: { start_date: "2026-04-15", end_date: "2026-04-20", tab: "history" }

      expect(response).to redirect_to(onboarding_tab_admin_hotel_path(hotel, tab: "history"))
      expect(flash[:notice]).to eq("Onboarding period updated.")
      expect(hotel.reload.onboarding_start_date).to eq(Date.new(2026, 4, 15))
      expect(hotel.onboarding_end_date).to eq(Date.new(2026, 4, 20))
    end

    it "rejects an end date before the start date without changing the hotel" do
      expect {
        post save_onboarding_period_admin_hotel_path(hotel),
             params: { start_date: "2026-04-20", end_date: "2026-04-15" }
      }.not_to change { hotel.reload.attributes.slice("onboarding_start_date", "onboarding_end_date") }

      expect(response).to redirect_to(onboarding_admin_hotel_path(hotel))
      expect(flash[:alert]).to eq("The end date must be on or after the start date.")
    end

    it "rejects missing or malformed dates without changing the hotel" do
      expect {
        post save_onboarding_period_admin_hotel_path(hotel),
             params: { start_date: "not-a-date", end_date: "", tab: "unknown" }
      }.not_to change { hotel.reload.attributes.slice("onboarding_start_date", "onboarding_end_date") }

      expect(response).to redirect_to(onboarding_admin_hotel_path(hotel))
      expect(flash[:alert]).to eq("Enter a valid start and end date.")
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

  describe "HTML training session mutations" do
    let(:hotel) { create(:hotel, account: admin_account, status: "pending_review") }
    let(:training_path) { onboarding_tab_admin_hotel_path(hotel, tab: "training") }
    let!(:session) do
      create(
        :onboarding_session,
        hotel:,
        trainer_name: "Training Owner",
        scheduled_at: 1.hour.ago
      )
    end

    it "returns creates to the training tab" do
      post admin_hotel_onboarding_sessions_path(hotel),
           params: {
             trainer_name: "New Trainer",
             scheduled_at: 1.day.from_now.iso8601,
             meeting_link: "https://meet.example.com/new"
           }

      expect(response).to redirect_to(training_path)
    end

    it "returns updates to the training tab" do
      patch admin_hotel_onboarding_session_path(hotel, session),
            params: { trainer_name: "Updated Trainer" }

      expect(response).to redirect_to(training_path)
    end

    it "returns completions to the training tab" do
      post complete_admin_hotel_onboarding_session_path(hotel, session)

      expect(response).to redirect_to(training_path)
    end

    it "returns cancellations to the training tab" do
      post cancel_admin_hotel_onboarding_session_path(hotel, session),
           params: { cancel_reason: "The property requested another date." }

      expect(response).to redirect_to(training_path)
    end

    it "returns deletions to the training tab" do
      delete admin_hotel_onboarding_session_path(hotel, session)

      expect(response).to redirect_to(training_path)
    end
  end

  describe "GET /admin/hotels/:id/onboarding/training with completed sessions" do
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
      get onboarding_tab_admin_hotel_path(hotel, tab: "training", format: :html)

      expect(response).to have_http_status(:ok)

      doc = Nokogiri::HTML(response.body)
      session_row = doc.at_css("#" + dom_id(completed_session))
      expect(session_row.text).to include("Completed Trainer")
      expect(session_row.text).not_to include("Delete")
    end
  end

  describe "POST /admin/hotels/:id/onboarding/setup_lock" do
    let(:hotel) { create(:hotel, account: admin_account, status: "setup") }

    it "turns the setup lock on and back off" do
      post toggle_setup_lock_admin_hotel_path(hotel)

      expect(response).to redirect_to(onboarding_admin_hotel_path(hotel))
      expect(hotel.reload.setup_lock_enabled).to be true

      post toggle_setup_lock_admin_hotel_path(hotel)

      expect(hotel.reload.setup_lock_enabled).to be false
    end

    it "offers the toggle on the onboarding page while the hotel is in setup" do
      get onboarding_admin_hotel_path(hotel)

      expect(response.body).to include("Enable setup lock")
    end

    it "still offers the toggle while the hotel is awaiting review" do
      hotel.update!(status: "pending_review")

      get onboarding_admin_hotel_path(hotel)

      expect(response.body).to include("Enable setup lock")
    end

    it "does not offer the toggle once the hotel is live" do
      hotel.update!(status: "live")

      get onboarding_admin_hotel_path(hotel)

      expect(response.body).not_to include("setup lock")
    end
  end
end
