require 'rails_helper'

RSpec.describe 'HotelPortal::Settings', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:ai_concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:hotel) { create(:hotel, account: account, status: 'registered', plan: plan, allow_boat_information: false) }
  let(:role) { create(:role, account: account, slug: 'hotel_owner', name: 'Hotel Owner') }

  before do
    Permission.find_or_create_by!(slug: 'manage_account') { |permission| permission.name = 'Manage Account' }
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |permission| permission.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_account'))
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_hotel_profile'))
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    create(:plan_feature, plan: plan, feature: ai_concierge_page_feature, enabled: true)
    sign_in_as(user)
  end

  describe 'GET /hotel/settings with legacy hotel_id param' do
    it 'redirects to the canonical hotel-scoped path' do
      get legacy_hotel_settings_path, params: { hotel_id: hotel.id }
      follow_redirect!

      expect(response).to redirect_to(hotel_general_settings_path(hotel))
    end
  end

  describe "GET /hotel/:hotel_id/settings" do
    it "uses the General group URL for notification settings" do
      expect(hotel_notification_settings_path(hotel)).to eq("/hotel/#{hotel.to_param}/settings/general/notifications")
    end

    it "permanently redirects the old Guest Content notification URL" do
      get "/hotel/#{hotel.to_param}/settings/guest-content/notifications"

      expect(response).to redirect_to(hotel_notification_settings_path(hotel))
      expect(response).to have_http_status(:moved_permanently)
    end

    it "permanently redirects the settings root to General" do
      get hotel_settings_path(hotel)

      expect(response).to redirect_to(hotel_general_settings_path(hotel))
      expect(response).to have_http_status(:moved_permanently)
    end

    it "uses the shared heading for General settings pages" do
      {
        hotel_general_settings_path(hotel) => "General Settings",
        hotel_rates_settings_path(hotel) => "General Settings",
        hotel_ai_concierge_settings_path(hotel) => "AI Concierge",
        hotel_notification_settings_path(hotel) => "General Settings",
        hotel_banking_details_settings_path(hotel) => "Banking Details"
      }.each do |path, expected_heading|
        get path

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.css("h1").map { |heading| heading.text.squish }).to eq([ expected_heading ])
      end
    end

    it "shows concierge QR entry when AI concierge page is enabled" do
      get hotel_general_settings_path(hotel)

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      trigger = document.at_css("a[href='#{hotel_concierge_qr_path(hotel)}'][data-turbo-frame='concierge_qr_dialog']")
      expect(trigger.text.squish).to eq("View QR")
      expect(document.at_css("turbo-frame#concierge_qr_dialog")).to be_present
    end

    it "renders the guest registration card field selection" do
      get hotel_general_settings_path(hotel)

      expect(response).to have_http_status(:ok)
      grc_settings = Nokogiri::HTML(response.body).at_css("#guest-registration-card")
      expect(grc_settings["class"]).to include("scroll-mt-6")
      expect(grc_settings["class"]).not_to include("border-t", "bg-card", "shadow-sm")
    end

    it "renders General as a two-column section workspace with Panels UI controls" do
      get hotel_general_settings_path(hotel)

      document = response.parsed_body
      form = document.at_css("form[action='#{hotel_general_settings_path(hotel)}']")
      expect(form["class"]).to include("gap-y-10", "lg:grid-cols-2")
      expect(form.css("section h2").map { |heading| heading.text.squish }).to eq(
        [ "General Setup", "Operation Times", "Guest Registration Card", "Localization & Security" ]
      )
      expect(form.css(".panel-metric-card").size).to eq(2)
      expect(form.at_css("[data-testid='guest-portal-card'].panel-card")).to be_present
      expect(form.css(".panel-time-picker").size).to eq(4)
      expect(form.at_css("[data-testid='localization-fields-grid']")["class"]).to include("items-start")
      expect(form.at_css(".panel-combobox select[name='hotel[time_zone]']")).to be_present
      expect(form.at_css(".panel-combobox select[name='hotel[default_currency]']")).to be_present
      expect(form.text).to include("Used for local check-in times, reports, and automated guest messages.")
      expect(form.css(".panel-switch input[role='switch']").size).to be >= 1
    end

    it "renders Banking Details as a cardless two-column workspace with Panels UI controls" do
      get hotel_banking_details_settings_path(hotel)

      document = response.parsed_body
      form = document.at_css("form[action='#{hotel_banking_details_settings_path(hotel)}']")
      expect(form["class"]).to include("gap-y-10", "lg:grid-cols-2")
      expect(form.css("section h2").map { |heading| heading.text.squish }).to eq([ "Banking Details" ])
      expect(form.at_css("section")["class"].to_s).not_to include("lg:col-span-2")
      expect(form.at_css("section .space-y-4")).to be_present
      expect(form.css("section.rounded-2xl, section.bg-card, section.shadow-sm")).to be_empty
      expect(form.css(".panel-form-field").size).to eq(3)
      expect(form.at_css(".panel-input[name='account[banking_detail_attributes][account_holder_name]']")).to be_present
      expect(form.at_css(".panel-input[name='account[banking_detail_attributes][account_number]']")).to be_present
      expect(form.at_css(".panel-combobox select[name='account[banking_detail_attributes][bank_name]']")).to be_present
      expect(form.css("select[name='account[banking_detail_attributes][bank_name]'] option").map(&:text)).to include("Maybank", "CIMB")
      expect(form.at_css("section button[type='submit']").text.squish).to eq("Save Banking Details")
    end

    it "renders AI Concierge as a left-column field stack with Panels UI controls" do
      get hotel_ai_concierge_settings_path(hotel)

      document = response.parsed_body
      form = document.at_css("form[action='#{hotel_ai_concierge_settings_path(hotel)}']")
      section = form.at_css("section")

      expect(form["class"]).to include("gap-y-10", "lg:grid-cols-2")
      expect(form.css("section h2").map { |heading| heading.text.squish }).to eq([ "AI Concierge Configuration" ])
      expect(section["class"].to_s).not_to include("lg:col-span-2")
      expect(section.at_css(".space-y-4")).to be_present
      expect(form.css("section.rounded-2xl, section.bg-card, section.shadow-sm")).to be_empty
      switch = section.at_css(".panel-switch")
      expect(switch["data-variant"]).to eq("card")
      expect(switch.at_css("input[name='hotel[ai_provider_enabled]']")).to be_present
      expect(section.css(".panel-form-field").size).to eq(3)
      expect(section.css(".panel-select-menu").size).to eq(2)
      expect(section.at_css(".panel-input[name='hotel[ai_provider_key]']")).to be_present
      expect(section.at_css("button[type='submit']").text.squish).to eq("Save AI Concierge Configuration")
    end

    it "normalizes legacy 12-hour operation times for the Panels UI time pickers" do
      create(:property_policy, hotel: hotel, check_in_time: "2:00 PM", check_out_time: "11:00 AM")

      get hotel_general_settings_path(hotel)

      document = response.parsed_body
      expect(document.at_css("#hotel_property_policy_attributes_check_in_time")["value"]).to eq("14:00")
      expect(document.at_css("#hotel_property_policy_attributes_check_out_time")["value"]).to eq("11:00")
    end

    it "renders Notifications as two columns with five independent Panels UI cards" do
      get hotel_notification_settings_path(hotel)

      document = response.parsed_body
      section = document.at_css("section[aria-labelledby='communication-notifications-heading']")
      expect(section.at_css(".grid.lg\\:grid-cols-2")).to be_present
      expect(section.css("article.panel-card").size).to eq(5)
      expect(section.css("article.panel-card[data-dividers='none']").size).to eq(5)
      expect(section.css("article.panel-card").first(2).map { |card| card["data-notification-type"] }).to eq(
        %w[check_in_confirmation check_out_receipt_message]
      )
      expect(section.css("form[action='#{hotel_notification_settings_path(hotel)}']").size).to eq(5)
      in_stay_wrapper = section.at_css("[data-notification-type='in_stay_guest_messaging']").ancestors.find { |node| node["class"].to_s.include?("lg:col-span-2") }
      expect(in_stay_wrapper).to be_present
      expect(section.at_css("input[name='notification_config[settings][review_link]']")).to be_present
      expect(section.at_css("input[name='notification_config[settings][rules][mid_stay][time]']")).to be_present
    end

    it "shows setup tabs in the settings tab bar" do
      get hotel_general_settings_path(hotel)

      expect(response).to have_http_status(:ok)
      tabs = response.parsed_body.at_css(%([data-testid="settings-tabs"] .tabs-root))
      expect(tabs).to be_present
      expect(tabs["class"]).not_to include("max-w-")
      expect(response.body).not_to include(%(data-testid="settings-setup-shortcuts"))
    end

    it "uses the dedicated flat settings navigation and portal breadcrumbs" do
      hotel.update!(status: "approved")
      manage_users = Permission.find_or_create_by!(slug: "manage_users") { |permission| permission.name = "Manage Users" }
      RolePermission.find_or_create_by!(role: role, permission: manage_users)
      get hotel_general_settings_path(hotel)

      document = response.parsed_body
      sidebar = document.at_css("#hotel-settings-sidebar")
      expect(sidebar).to be_present
      expect(document.at_css("#hotel-sidebar")).to be_nil
      expect(sidebar["data-sidebar-mode"]).to be_nil
      items = sidebar.css(".panel-sidebar__section-items > .panel-sidebar__item")
      expect(items.map { |item| item.at_css("[data-sidebar-presentation='expanded'] .panel-sidebar__label").text.squish }).to eq(
        [ "General", "Property", "Commercial", "Finance", "Guest Content", "Team" ]
      )
      expect(sidebar.text).not_to include("Back to previous page")

      breadcrumb_items = document.css("#hotel-breadcrumb .breadcrumb-item")
      expect(breadcrumb_items[0].at_css("a")&.text&.squish).to eq("Settings")
      expect(breadcrumb_items[1].text.squish).to eq("General")
      expect(breadcrumb_items[1].at_css("a, button")).to be_nil
      expect(breadcrumb_items[2].at_css("a")&.text&.squish).to eq("General")
      expect(breadcrumb_items[2].at_css("button[aria-label='Open General navigation']")).to be_present
      expect(breadcrumb_items[2].css("[role='menuitem']").map { |item| item.text.squish }).to eq(
        [ "General", "Rate Settings", "Notifications", "Plan & Billing" ]
      )
    end

    it "uses permission-filtered tabs in the active settings breadcrumb menu" do
      get hotel_banking_details_settings_path(hotel)

      breadcrumb_items = response.parsed_body.css("#hotel-breadcrumb .breadcrumb-item")
      expect(breadcrumb_items[1].text.squish).to eq("Finance")
      expect(breadcrumb_items[1].at_css("a, button")).to be_nil
      expect(breadcrumb_items[2].at_css("button[aria-label='Open Banking Details navigation']")).to be_present
      expect(breadcrumb_items[2].css("[role='menuitem']").map { |item| item.text.squish }).to eq(
        [ "Banking Details", "Transaction Code Reference" ]
      )
    end

    it "renders Commercial as a sidebar menu with Taxes & Fees as its active child" do
      hotel.update!(status: "approved")
      get hotel_taxes_fees_path(hotel)

      document = response.parsed_body
      commercial = document.css("#hotel-settings-sidebar [data-sidebar-group-item]").find do |item|
        item.at_css("a.panel-sidebar__child[href='#{hotel_taxes_fees_path(hotel)}']").present?
      end

      expect(commercial).to be_present
      expect(commercial.at_css(".panel-sidebar__group-trigger")&.text&.squish).to eq("Commercial")
      expect(commercial.at_css("a.panel-sidebar__child[href='#{hotel_taxes_fees_path(hotel)}']")&.text&.squish).to eq("Taxes & Fees")
      expect(commercial.at_css("a.panel-sidebar__child[aria-current='page']")&.text&.squish).to eq("Taxes & Fees")
      expect(document.at_css("[data-testid='settings-tabs']")).to be_nil
    end

    it "places the admin portal destination in the footer for superadmins" do
      hotel.update!(status: "approved")
      sign_in_as(create(:user, :superadmin, account: account))

      get hotel_general_settings_path(hotel)

      footer_link = response.parsed_body.at_css("#hotel-settings-sidebar .panel-sidebar__footer a[href='#{admin_dashboard_path}']")
      expect(footer_link.text.squish).to eq("Go to Admin Portal")
      expect(footer_link["target"]).to eq("_blank")
      expect(footer_link["rel"]).to eq("noopener noreferrer")
    end

    it "does not expose resource-owned pages as settings panels" do
      get hotel_general_settings_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(%(data-tab-name="hotel_details"))
      expect(response.body).not_to include(%(data-tab-name="taxes_fees"))
      expect(response.body).not_to include(%(data-testid="settings-hotel-details-panel"))
      expect(response.body).not_to include(%(data-testid="settings-taxes-fees-panel"))
    end

    it "redirects legacy tab URLs to canonical resource paths" do
      get hotel_settings_path(hotel, tab: "general")
      expect(response).to redirect_to(hotel_general_settings_path(hotel))
      expect(response).to have_http_status(:moved_permanently)

      get hotel_settings_path(hotel, tab: "ai")
      expect(response).to redirect_to(hotel_ai_concierge_settings_path(hotel))
      expect(response).to have_http_status(:moved_permanently)

      get hotel_settings_path(hotel, tab: "notifications")
      expect(response).to redirect_to(hotel_notification_settings_path(hotel))
      expect(response).to have_http_status(:moved_permanently)

      get hotel_settings_path(hotel, tab: "banking")
      expect(response).to redirect_to(hotel_banking_details_settings_path(hotel))
      expect(response).to have_http_status(:moved_permanently)

      get hotel_settings_path(hotel, tab: "hotel_details")
      expect(response).to redirect_to(edit_hotel_profile_path(hotel))
      expect(response).to have_http_status(:moved_permanently)

      get hotel_settings_path(hotel, tab: "taxes_fees")
      expect(response).to redirect_to(hotel_taxes_fees_path(hotel))
      expect(response).to have_http_status(:moved_permanently)
    end

    it "hides concierge QR entry when AI concierge page is excluded from plan" do
      hotel.plan.plan_features.find_by!(feature: ai_concierge_page_feature).update!(enabled: false)

      get hotel_general_settings_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.at_css("a[data-turbo-frame='concierge_qr_dialog']")).to be_nil
      expect(response.parsed_body.at_css("turbo-frame#concierge_qr_dialog")).to be_nil
    end
  end

  describe "GET /hotel/:hotel_id/settings/general/rates" do
    it "renders the rate settings tab with a rate plan list and a New Rate Plan trigger" do
      get hotel_rates_settings_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Rate Settings")
      expect(response.body).to include("New rate plan")
      expect(Nokogiri::HTML(response.body).at_css('[data-testid="rate-plans-registry"]')).to be_present
    end

    it "splits standard plans onto their own tab, so system rows do not bury composed plans" do
      room_type = create(:room_type, hotel: hotel, name: "Ocean Villa")
      composed = create(:rate_plan, hotel: hotel, name: "Breakfast Rate", kind: "custom", room_type: room_type)
      standard = room_type.rate_plans.find_by(kind: "standard")

      get hotel_rates_settings_path(hotel)
      plans_tab = Nokogiri::HTML(response.body)
      expect(plans_tab.at_css('[data-testid="rate-plans-registry"]')).to be_present
      expect(plans_tab.at_css("#rate-plan-row-#{composed.id}")).to be_present
      expect(plans_tab.at_css("#rate-plan-row-#{standard.id}")).to be_nil

      get hotel_rates_settings_path(hotel, view: "standard")
      standard_tab = Nokogiri::HTML(response.body)
      expect(standard_tab.at_css('[data-testid="standard-rates-registry"]')).to be_present
      expect(standard_tab.at_css("#rate-plan-row-#{standard.id}")).to be_present
      expect(standard_tab.at_css("#rate-plan-row-#{composed.id}")).to be_nil
    end

    it "hides the Walk-in Rate plan row when the hotel is pax_pricing_only" do
      hotel.update!(allow_pax_pricing: true, pax_pricing_only: true)
      create(:rate_plan, hotel: hotel, name: "Standard Rate", sell_mode: "per_person")
      create(:rate_plan, :walk_in_tier, hotel: hotel, sell_mode: "per_room")

      get hotel_rates_settings_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Walk-in Rate")
    end
  end

  describe "GET /hotel/:hotel_id/concierge_qr" do
    it "renders an almost-full Panels UI dialog as a Turbo Frame payload" do
      get hotel_concierge_qr_path(hotel), headers: { "Turbo-Frame" => "concierge_qr_dialog" }

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      frame = document.at_css("turbo-frame#concierge_qr_dialog")
      dialog = frame.at_css("dialog#concierge-qr-code-dialog")

      expect(response.body).not_to include("<!DOCTYPE html>")
      expect(frame.at_css("[data-controller='concierge-qr']")).to be_present
      expect(dialog["class"]).to include("w-[calc(100vw-3rem)]", "h-[calc(100vh-3rem)]")
      expect(dialog.text.squish).to include("Concierge QR Code", hotel.name, "Concierge URL")
      expect(frame.at_css("#concierge-qr-print-area svg")).to be_present
      expect(frame.css("button, a").map { |element| element.text.squish }).to include(
        "Print", "Download SVG", "Download PNG", "Copy URL"
      )
      expect(frame.at_css("a[href='#{hotel_concierge_qr_path(hotel, format: :svg)}'][data-turbo='false']")).to be_present
      expect(frame.at_css("a[href='#{hotel_concierge_qr_path(hotel, format: :png)}'][data-turbo='false']")).to be_present
    end

    it "keeps SVG and PNG downloads as attachments" do
      {
        svg: "image/svg+xml",
        png: "image/png"
      }.each do |format, media_type|
        get hotel_concierge_qr_path(hotel, format: format)

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq(media_type)
        expect(response.headers["Content-Disposition"]).to include(
          "attachment",
          "concierge-qr-#{hotel.slug}.#{format}"
        )
      end
    end

    it "redirects when AI concierge page is excluded from plan" do
      hotel.plan.plan_features.find_by!(feature: ai_concierge_page_feature).update!(enabled: false)

      [ nil, :svg, :png ].each do |format|
        get hotel_concierge_qr_path(hotel, format: format)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("This feature isn't included in your plan. Upgrade to access it.")
      end
    end
  end

  describe 'PATCH /hotel/settings' do
    it "updates guest registration card fields" do
      patch hotel_general_settings_path(hotel), params: {
        form_id: "hotel_settings",
        hotel: { guest_registration_card_fields: %w[phone room_type check_in] }
      }

      expect(response).to redirect_to(hotel_general_settings_path(hotel))
      expect(hotel.reload.guest_registration_card_fields).to eq(%w[phone room_type check_in])
    end

    it "renders the Boat Settings tab with its slots and meal times" do
      hotel.update!(allow_boat_information: true)
      create(:hotel_boat_setting, hotel: hotel)
      create(:hotel_boat_schedule, hotel: hotel, kind: "boat_in", time: "09:30", has_lunch: true)
      create(:hotel_boat_schedule, hotel: hotel, kind: "boat_out", time: "16:45", has_breakfast: true)

      get hotel_boat_settings_path(hotel)

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("h1, h2").text).to include("Boat Settings")
      expect(document.text).to include("Meal Service Times", "Boat Arrival (Boat-in)", "Boat Departure (Boat-out)")
      expect(document.at_css("[data-testid='settings-tabs']").text).to include("Boat Settings")
      expect(response.body).to include("09:30", "16:45")
    end

    it "hides Save until a slot changes, keeps the new-slot card collapsed, and wires each button to its own form" do
      hotel.update!(allow_boat_information: true)
      slot = create(:hotel_boat_schedule, hotel: hotel, kind: "boat_in", time: "09:30")

      get hotel_boat_settings_path(hotel)

      document = Nokogiri::HTML(response.body)
      row = document.at_css("li[data-controller='boat-slot']:not([hidden])")

      # Save and Discard are hidden on the buttons themselves -- no wrapper, so
      # they stay direct children of the group -- and the row's Stimulus
      # controller reveals both once the row differs from what was saved.
      save = row.at_css("button[data-boat-slot-target='save']")
      expect(save["hidden"]).not_to be_nil
      expect(save["form"]).to eq("boat-slot-#{slot.id}")

      # Discard resets the edit form rather than submitting anything, which is
      # the only way out of a dirty row that is not Save.
      discard = row.at_css("button[data-boat-slot-target='discard']")
      expect(discard["hidden"]).not_to be_nil
      expect(discard["type"]).to eq("button")
      expect(discard["data-action"]).to eq("boat-slot#discard")
      expect(row.at_css("form[data-boat-slot-target='form']")["id"]).to eq("boat-slot-#{slot.id}")

      # Retire submits its own form, so the two live in one button group
      # without nesting a form inside a form.
      retire = row.at_css("button[form='boat-slot-#{slot.id}-state']")
      expect(retire).to be_present
      expect(retire["aria-label"]).to eq("Retire slot 09:30")
      state_form = document.at_css("form#boat-slot-#{slot.id}-state")
      expect(state_form.at_css("input[name='_method']")["value"]).to eq("delete")

      # All three are icon-only direct children of one group -- a wrapper would
      # drop out of the selectors that join their corners -- and neither
      # secondary button falls back to the primary variant that an unknown
      # variant name silently produces.
      group = row.at_css(".panel-button-group")
      expect(group.css("> button").size).to eq(3)
      expect(group.css("button").map { |button| button.text.squish }).to all(be_empty)
      expect(retire["data-variant"]).to eq("neutral")
      expect(discard["data-variant"]).to eq("neutral")

      # The Add trigger sits in the section header, and its card starts hidden.
      section = document.at_css("section[data-controller='boat-slots']")
      expect(section.at_css("[data-boat-slots-target='trigger']").text).to include("Add slot")
      expect(section.at_css("li[data-boat-slots-target='card']")["hidden"]).not_to be_nil
    end

    it "saves meal service times on the Boat Settings tab" do
      hotel.update!(allow_boat_information: true)

      patch hotel_boat_settings_path(hotel), params: {
        form_id: "boat_settings",
        hotel: { hotel_boat_setting_attributes: { breakfast_time: "08:00", lunch_time: "12:00", dinner_time: "19:00" } }
      }

      expect(response).to redirect_to(hotel_boat_settings_path(hotel))
      expect(hotel.reload.hotel_boat_setting.breakfast_time.strftime("%H:%M")).to eq("08:00")
      expect(hotel.hotel_boat_setting.dinner_time.strftime("%H:%M")).to eq("19:00")
    end

    it "adds a slot, pre-ticking its meals from the property's service times" do
      hotel.update!(allow_boat_information: true)
      create(:hotel_boat_setting, hotel: hotel, breakfast_time: "08:00", lunch_time: "12:00", dinner_time: "19:00")

      post hotel_boat_schedule_slots_path(hotel), params: {
        hotel_boat_schedule: { kind: "boat_in", time: "09:30" }
      }

      slot = hotel.hotel_boat_schedules.find_by(kind: "boat_in", time: "09:30")
      # 09:30 lands after breakfast is served but before lunch and dinner.
      expect(slot.meals).to eq(%i[lunch dinner])
    end

    it "retires a slot rather than destroying it, so booked guests keep it" do
      hotel.update!(allow_boat_information: true)
      slot = create(:hotel_boat_schedule, hotel: hotel, kind: "boat_in", time: "09:30")

      delete hotel_boat_schedule_slot_path(hotel, slot)

      expect(hotel.hotel_boat_schedules.count).to eq(1)
      expect(slot.reload).to be_archived
      expect(Boats::Schedule.new(hotel.reload).in_times).to be_empty

      patch hotel_boat_schedule_slot_restore_path(hotel, slot)
      expect(slot.reload).not_to be_archived
    end

    it "rejects a duplicate slot at the same time and kind" do
      hotel.update!(allow_boat_information: true)
      create(:hotel_boat_schedule, hotel: hotel, kind: "boat_in", time: "09:30")

      expect {
        post hotel_boat_schedule_slots_path(hotel), params: {
          hotel_boat_schedule: { kind: "boat_in", time: "09:30" }
        }
      }.not_to change(HotelBoatSchedule, :count)

      expect(flash[:alert]).to include("already has a slot at this time")
    end

    it "discards unknown guest registration card fields and allows none" do
      patch hotel_general_settings_path(hotel), params: {
        form_id: "hotel_settings",
        hotel: { guest_registration_card_fields: [ "", "unknown" ] }
      }

      expect(response).to redirect_to(hotel_general_settings_path(hotel))
      expect(hotel.reload.guest_registration_card_fields).to eq([])
    end

    it 'updates check-in notification settings and channels' do
      patch hotel_general_settings_path(hotel), params: {
        form_id: 'notification_settings',
        notification_config: {
          enabled: '1',
          channels: [ 'whatsapp', 'email' ]
        }
      }

      expect(response).to redirect_to(hotel_notification_settings_path(hotel))
      follow_redirect!
      expect(response.body).to include('Settings updated successfully.')

      config = NotificationConfig.find_by!(hotel: hotel, notification_type: 'check_in_confirmation')
      expect(config.enabled).to be(true)
      expect(config.channels).to match_array(%w[whatsapp email])
    end

    it 'allows disabling check-in notification while keeping selected channels' do
      NotificationConfig.create!(
        hotel: hotel,
        notification_type: 'check_in_confirmation',
        enabled: true,
        channels: %w[whatsapp],
        settings: {}
      )

      patch hotel_notification_settings_path(hotel), params: {
        form_id: 'notification_settings',
        notification_config: {
          enabled: '0',
          channels: [ 'email' ]
        }
      }

      expect(response).to redirect_to(hotel_notification_settings_path(hotel))
      config = NotificationConfig.find_by!(hotel: hotel, notification_type: 'check_in_confirmation')
      expect(config.enabled).to be(false)
      expect(config.channels).to eq([ 'email' ])
    end

    it 'updates post-stay review request settings' do
      patch hotel_notification_settings_path(hotel), params: {
        form_id: 'notification_settings',
        notification_config: {
          notification_type: 'post_stay_review_request',
          enabled: '1',
          channels: [ 'whatsapp', 'email' ],
          settings: {
            review_link: 'https://g.page/r/sample/review',
            send_delay_hours: '4'
          }
        }
      }

      expect(response).to redirect_to(hotel_notification_settings_path(hotel))
      config = NotificationConfig.find_by!(hotel: hotel, notification_type: 'post_stay_review_request')
      expect(config.enabled).to be(true)
      expect(config.channels).to match_array(%w[whatsapp email])
      expect(config.settings['review_link']).to eq('https://g.page/r/sample/review')
      expect(config.settings['send_delay_hours']).to eq(4)
    end

    it "updates pre-arrival notification settings with channels and stages" do
      patch hotel_notification_settings_path(hotel), params: {
        form_id: "notification_settings",
        notification_config: {
          notification_type: "pre_arrival_notification",
          enabled: "1",
          channels: [ "whatsapp", "email" ],
          settings: {
            stages: [ "d2", "d1" ]
          }
        }
      }

      expect(response).to redirect_to(hotel_notification_settings_path(hotel))
      config = NotificationConfig.find_by!(hotel: hotel, notification_type: "pre_arrival_notification")
      expect(config.enabled).to be(true)
      expect(config.channels).to match_array(%w[whatsapp email])
      expect(config.settings["stages"]).to eq(%w[d2 d1])
    end

    it "updates check-out receipt message settings with both channels" do
      patch hotel_notification_settings_path(hotel), params: {
        form_id: "notification_settings",
        notification_config: {
          notification_type: "check_out_receipt_message",
          enabled: "1",
          channels: [ "whatsapp", "email" ]
        }
      }

      expect(response).to redirect_to(hotel_notification_settings_path(hotel))
      config = NotificationConfig.find_by!(hotel: hotel, notification_type: "check_out_receipt_message")
      expect(config.enabled).to be(true)
      expect(config.channels).to match_array(%w[whatsapp email])
    end

    it "updates in-stay guest messaging settings with rules and quiet hours" do
      patch hotel_notification_settings_path(hotel), params: {
        form_id: "notification_settings",
        notification_config: {
          notification_type: "in_stay_guest_messaging",
          enabled: "1",
          channels: [ "whatsapp", "email" ],
          settings: {
            rules: {
              mid_stay: { enabled: "1", time: "12:00" },
              upsell: { enabled: "1", time: "17:00" },
              activity: { enabled: "0", time: "10:00" }
            },
            quiet_hours: {
              enabled: "1",
              start: "22:00",
              end: "08:00"
            }
          }
        }
      }

      expect(response).to redirect_to(hotel_notification_settings_path(hotel))
      config = NotificationConfig.find_by!(hotel: hotel, notification_type: "in_stay_guest_messaging")
      expect(config.enabled).to be(true)
      expect(config.channels).to match_array(%w[whatsapp email])
      expect(config.settings.dig("rules", "mid_stay", "enabled")).to be(true)
      expect(config.settings.dig("rules", "activity", "enabled")).to be(false)
      expect(config.settings.dig("quiet_hours", "start")).to eq("22:00")
      expect(config.settings.dig("quiet_hours", "end")).to eq("08:00")
    end

    it 'ignores tampered status params and updates allowed banking details' do
      patch hotel_banking_details_settings_path(hotel), params: {
        account: {
          status: 'suspended',
          banking_detail_attributes: {
            account_holder_name: 'Syarikat Maju Jaya Sdn Bhd',
            bank_name: 'Maybank',
            account_number: '5142 1234 5678'
          }
        }
      }

      expect(response).to redirect_to(hotel_banking_details_settings_path(hotel))
      follow_redirect!
      expect(response.body).to include('Settings updated successfully.')
      expect(hotel.reload.status).to eq('registered')
      banking_detail = account.reload.banking_detail
      expect(banking_detail.account_holder_name).to eq('Syarikat Maju Jaya Sdn Bhd')
      expect(banking_detail.bank_name).to eq('Maybank')
      expect(banking_detail.account_number).to eq('5142 1234 5678')
    end

    it 'rolls back hotel settings when property policy validation fails' do
      hotel.update!(default_currency: 'MYR')
      create(:property_policy, hotel: hotel, check_in_time: '2:00 PM', check_out_time: '11:00 AM')

      patch hotel_general_settings_path(hotel), params: {
        hotel: {
          default_currency: 'USD',
          property_policy_attributes: {
            check_in_time: '3:00 PM',
            check_out_time: ''
          }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      breadcrumb = response.parsed_body.at_css("#hotel-breadcrumb")
      items = breadcrumb.css(".breadcrumb-item")
      expect(items[0].at_css("a")&.text&.squish).to eq("Settings")
      expect(items[1].text.squish).to eq("General")
      expect(items[1].at_css("a, button")).to be_nil
      expect(items[2].at_css("button[aria-label='Open General navigation']")).to be_present

      hotel.reload
      expect(hotel.default_currency).to eq('MYR')

      property_policy = hotel.property_policy.reload
      expect(property_policy.check_in_time).to eq('2:00 PM')
      expect(property_policy.check_out_time).to eq('11:00 AM')
    end

    it 'does not allow hotel users to update payment gateway configuration' do
      patch hotel_general_settings_path(hotel), params: {
        payment_setting: {
          gateway: 'razorpay',
          api_key: 'rzp_test_key',
          secret_key: 'rzp_test_secret',
          webhook_secret: 'whsec_test',
          status: 'active'
        }
      }

      expect(response).to redirect_to(hotel_general_settings_path(hotel))
      follow_redirect!
      expect(response.body).to include('Payment gateway credentials are managed by superadmin.')
      expect(hotel.payment_settings.find_by(gateway: 'razorpay')).to be_nil
    end

    it 'updates ai concierge tone and provider configuration' do
      patch hotel_ai_concierge_settings_path(hotel), params: {
        form_id: 'ai_configuration',
        hotel: {
          ai_provider_enabled: '1',
          ai_concierge_tone: 'cheerful',
          ai_provider_name: 'openai',
          ai_provider_key: 'test-api-key'
        }
      }

      expect(response).to redirect_to(hotel_ai_concierge_settings_path(hotel))
      follow_redirect!
      expect(response.body).to include('Settings updated successfully.')

      hotel.reload
      expect(hotel.ai_provider_enabled).to be(true)
      expect(hotel.ai_concierge_tone).to eq('cheerful')
      expect(hotel.ai_provider_name).to eq('openai')
    end
  end
end
