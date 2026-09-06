# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::ObservationDeck", type: :request do
  let(:account) { create(:account, name: "Observation Deck Admin") }
  let(:superadmin) { create(:user, :superadmin, account: account, email: "observation-admin@example.com") }

  before { sign_in_as(superadmin) }

  describe "GET /admin/observation_deck" do
    it "renders standalone investigation workspace and settings" do
      get admin_observation_deck_index_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Observation Deck", "Last 24 hours", "Event stream", "Selected event inspector")
      expect(response.body).to include('id="entries_frame"', 'id="entry_detail_frame"', 'id="observation-settings"', 'id="observation-more-filters"')
      expect(response.body).to include('aria-haspopup="dialog"')
      expect(response.body).to include("Automatic retention", "Runs daily at 3:00 AM server time", "recent incidents remain available for investigation.")
      expect(response.body).to include('class="observation-deck__retention-notice"')
    end

    it "filters entries with persisted query parameters" do
      matching_entry = create(
        :observation_entry,
        entry_type: "request",
        request_id: "request-123",
        status: 404,
        duration: 1500,
        path: "GET /matching",
        tags: [ "incident", "booking:12" ],
        created_at: 30.minutes.ago
      )
      create(:observation_entry, entry_type: "sql", status: 200, duration: 10, path: "SELECT excluded", tags: [ "routine" ], created_at: 30.minutes.ago)
      create(:observation_entry, entry_type: "request", status: 500, duration: 2000, path: "GET /expired", tags: [ "incident" ], created_at: 2.hours.ago)

      get admin_observation_deck_index_path(
        time_range: "hour",
        entry_type: "request",
        status_group: "errors",
        request_id: matching_entry.request_id,
        min_duration: "1000",
        exact_status: "404",
        tags: "incident"
      )

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("GET /matching")
      expect(response.body).not_to include("SELECT excluded", "GET /expired")
      expect(response.body).to include("Time: Last hour", "Type: Request", "Status: Errors")
      expect(response.body).to include("time_range=hour", "entry_type=request", "status_group=errors", "request_id=request-123")
    end

    it "updates health and event stream through Turbo" do
      create(:observation_entry, entry_type: "request", status: 200, duration: 125)

      get admin_observation_deck_index_path, as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream])
      expect(response.body).to include('target="observation-health-strip"', 'target="entries_frame"')
    end

    it "applies the selected time range to health metrics" do
      create(:observation_entry, entry_type: "request", status: 200, duration: 100, created_at: 30.minutes.ago)
      create(:observation_entry, entry_type: "request", status: 500, duration: 900, created_at: 2.hours.ago)

      get admin_observation_deck_index_path(time_range: "hour")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Last hour")
      expect(response.body).to match(/Requests<\/dt>\s*<dd>1<\/dd>/)
      expect(response.body).to match(/Errors<\/dt>\s*<dd[^>]*>0/)
      expect(response.body).to match(/Avg latency<\/dt>\s*<dd>100\.0/)
    end

    it "keeps the payload column out of index queries" do
      create(:observation_entry, payload: { "large" => "payload" })
      statements = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |_name, _start, _finish, _id, payload| statements << payload[:sql] }

      get admin_observation_deck_index_path

      query = statements.find { |statement| statement.include?("FROM \"observation_entries\"") && statement.include?("SELECT") }
      expect(query).to be_present
      expect(query).not_to match(/\"payload\"/)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end

    it "renders pagination when the event stream has multiple pages" do
      create_list(:observation_entry, 51)

      get admin_observation_deck_index_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('aria-label="Event stream pagination"')
      expect(response.body).to include("panel-pagination")
    end

    it "links to integrations when no AI providers are configured" do
      get admin_observation_deck_index_path

      expect(response.body).to include("Configure AI Providers", admin_integrations_path)
    end

    it "shows only configured AI providers in settings" do
      AppConfig.set("openai_api_key", "openai-key")

      get admin_observation_deck_index_path

      expect(response.body).to include("OpenAI")
      expect(response.body).not_to include(">DeepSeek<", ">Claude<")
    end
  end

  describe "GET /admin/observation_deck/:id" do
    it "renders inspector tabs and chronological trace inside frame" do
      request_id = "request-trace"
      request_entry = create(:observation_entry, entry_type: "request", request_id:, path: "GET /orders", created_at: 2.minutes.ago)
      sql_entry = create(:observation_entry, entry_type: "sql", request_id:, path: "Order Load", payload: { "sql" => "SELECT * FROM orders" }, created_at: 1.minute.ago)

      get admin_observation_deck_path(sql_entry), headers: { "Turbo-Frame" => "entry_detail_frame" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="entry_detail_frame"', "Summary", "Trace", "Payload", "AI analysis")
      expect(response.body).to include(request_entry.path, sql_entry.path, "Current event", "Copy SQL")
    end

    it "returns recoverable inspector content when event was deleted" do
      missing_id = SecureRandom.uuid

      get admin_observation_deck_path(missing_id), headers: { "Turbo-Frame" => "entry_detail_frame" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("This event is no longer available")
    end
  end

  describe "POST /admin/observation_deck/:id/analyze" do
    it "renders a retryable inline error when analysis fails" do
      entry = create(:observation_entry, status: 500, duration: 250)
      analyzer = instance_double(PlatformControl::AiAnalyzerService, analyze: { error: "OpenAI API request failed: rate limit" })
      allow(PlatformControl::AiAnalyzerService).to receive(:new).with(entry).and_return(analyzer)

      post analyze_admin_observation_deck_path(entry), as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("OpenAI API request failed: rate limit", "Retry analysis")
    end
  end

  describe "POST /admin/observation_deck/update_config" do
    it "saves configured provider as Observation Deck provider" do
      AppConfig.set("openai_api_key", "openai-key")

      post update_config_admin_observation_deck_index_path, params: { observation_deck_ai_provider: "openai" }

      expect(AppConfig.get("observation_deck_ai_provider")).to eq("openai")
      expect(AppConfig.get("ai_provider")).to be_nil
    end

    it "does not save unconfigured provider" do
      AppConfig.set("openai_api_key", "openai-key")

      post update_config_admin_observation_deck_index_path, params: { observation_deck_ai_provider: "deepseek" }

      expect(AppConfig.get("observation_deck_ai_provider")).to be_nil
    end
  end
end
