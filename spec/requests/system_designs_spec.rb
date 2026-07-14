# frozen_string_literal: true

require "rails_helper"

RSpec.describe "System design showcase", type: :request do
  PREVIEW_PARTIALS = %w[
    accordion_preview
    alert_preview
    avatar_preview
    badge_preview
    banner_preview
    breadcrumb_preview
    button_preview
    button_group_preview
    card_preview
    checkbox_preview
    collapsible_preview
    combobox_preview
    date_picker_preview
    date_time_picker_preview
    dialog_preview
    dropdown_menu_preview
    file_upload_preview
    form_fields_preview
    form_submission_preview
    kbd_preview
    loading_preview
    metric_card_preview
    multi_select_preview
    native_select_preview
    navbar_preview
    page_header_preview
    popover_preview
    radio_preview
    scroll_area_preview
    select_menu_preview
    separator_preview
    sheet_preview
    sidebar_preview
    switch_preview
    table_preview
    tabs_preview
    time_picker_preview
    toast_preview
    tooltip_preview
  ].freeze

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
    expect(response.body).to include("button-group-preview-heading")
    expect(response.body).to include("panel-button-group")
    expect(response.body).to include('data-slot="button-group-text"')
    expect(response.body).to include('data-slot="button-group-separator"')
    expect(response.body).to include("page-header-preview-heading")
    expect(response.body).to include("panel-page-header")
    expect(response.body).to include("badge-preview-heading")
    expect(response.body).to include("panel-badge-rounded")
    expect(response.body).to include("avatar-preview-heading")
    expect(response.body).to include("panel-avatar")
    expect(response.body).to include("panel-avatar-group")
    expect(response.body).to include("data:image/png;base64,broken-preview-image")
    expect(response.body).not_to include("/missing-avatar-preview.png")
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
    expect(response.body).to include("accordion-preview-heading")
    expect(response.body).to include("panel-accordion--default")
    expect(response.body).to include("panel-accordion--bordered")
  end

  it "renders the Turbo form-submission preview with its frame and controller" do
    get system_design_path

    expect(response.body).to include("form-submission-preview-heading")
    expect(response.body).to include('data-controller="system-designs--form-submission-preview"')
    expect(response.body).to include('id="system-design-reservation-form"')
    expect(response.body).to include('data-turbo-submits-with="Saving…"')
  end

  it "lists and renders every preview in alphabetical order" do
    get system_design_path

    document = Nokogiri::HTML(response.body)
    previews = document.css("[data-preview-partial]")
    desktop_links = document.css('aside nav[aria-label="Component previews"] a')

    expect(previews.map { |preview| preview["data-preview-partial"] }).to eq(PREVIEW_PARTIALS)
    expect(desktop_links.map { |link| link.text.strip.downcase }).to eq(
      desktop_links.map { |link| link.text.strip.downcase }.sort
    )
    expect(document.css('nav[aria-label="Component previews"]').size).to eq(2)

    PREVIEW_PARTIALS.each do |partial|
      anchor = partial.tr("_", "-")
      preview = document.at_css("##{anchor}")

      expect(preview).to be_present
      expect(preview.text).to include("_#{partial}.html.erb")
      expect(document.css("a[href='##{anchor}']").size).to eq(2)
    end
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
