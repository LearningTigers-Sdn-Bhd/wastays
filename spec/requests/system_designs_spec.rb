# frozen_string_literal: true

require "rails_helper"

RSpec.describe "System design showcase", type: :request do
  it "uses its asset-enabled layout without application chrome" do
    get system_design_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)

    expect(response.body).to include("data-system-design-showcase")
    expect(response.body).to include("button-preview-heading")
    expect(response.body).to include("panel-button")
    expect(response.body).to include("file-upload-preview-heading")
    expect(response.body).to include("panel-dropzone")
    expect(response.body).to include("panel-attachment")
    expect(response.body).to include("page-header-preview-heading")
    expect(response.body).to include("panel-page-header")
    expect(response.body).to include("badge-preview-heading")
    expect(response.body).to include("panel-badge-rounded")
    expect(response.body).to include("alert-preview-heading")
    expect(response.body).to include("panel-alert")
    expect(response.body).to include("Review")
    expect(response.body).to include("banner-preview-heading")
    expect(response.body).to include("panel-banner")
    expect(response.body).to include("Claim offer")
    expect(response.body).to include("Maybe later")
    expect(response.body).to include("loading-preview-heading")
    expect(response.body).to include("panel-skeleton")
    expect(response.body).to include("panel-spinner")
    expect(response.body).to include("panel-progress")
    expect(response.body).to include("date-picker-preview-heading")
    expect(response.body).to include("panel-date-picker")
    expect(response.body).to include("panels-ui--date-picker")
    expect(response.body).to include("calendar-date")
    expect(response.body).to include("time-picker-preview-heading")
    expect(response.body).to include("panel-time-picker")
    expect(response.body).to include("panels-ui--time-picker")
    expect(response.body).to include("panel-time-control")
    expect(response.body).to include("date-time-picker-preview-heading")
    expect(response.body).to include("panel-date-time-picker")
    expect(response.body).to include("panels-ui--date-time-picker")
    expect(response.body).to include("separator-preview-heading")
    expect(response.body).to include('class="panel-separator')
    expect(response.body).to include('data-orientation="horizontal"')
    expect(response.body).to include('data-orientation="vertical"')
    expect(response.body).to include("kbd-preview-heading")
    expect(response.body).to include('class="panel-kbd"')
    expect(response.body).to include("collapsible-preview-heading")
    expect(response.body).to include("panel-collapsible")
    expect(response.body).to include("checkbox-preview-heading")
    expect(response.body).to include("panel-checkbox")
    expect(response.body).to include('data-toast-variant="danger"')
    expect(response.body).to include('data-variant="destructive"')
    expect(response.body).to include("stylesheet")
    expect(response.body).to include("importmap")
    expect(document.at_css('body > header, body > nav[aria-label="Global"], body > footer')).to be_nil
    expect(response.body).not_to include("widget.1automations.com")
  end

  it "renders the Turbo form-submission preview with its frame and controller" do
    get system_design_path

    expect(response.body).to include("form-submission-preview-heading")
    expect(response.body).to include('data-controller="system-designs--form-submission-preview"')
    expect(response.body).to include('id="system-design-reservation-form"')
    expect(response.body).to include('data-turbo-submits-with="Saving…"')
  end

  describe "POST submit-form" do
    it "swaps in a fresh form on valid input" do
      post system_design_submit_form_path,
           params: { reservation_request: { guest_name: "Ada Lovelace", email: "ada@example.com", nights: "2" } }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="system-design-reservation-form"')
      expect(response.body).to include("Saved — the form reset.")
      expect(response.body).not_to include("panel-form-field__error")
    end

    it "re-renders with inline errors and a 422 on invalid input" do
      post system_design_submit_form_path,
           params: { reservation_request: { guest_name: "", email: "not-an-email", nights: "0" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('id="system-design-reservation-form"')
      expect(response.body).to include("panel-form-field__error")
    end
  end
end
