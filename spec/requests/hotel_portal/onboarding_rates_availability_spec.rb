# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Onboarding rates and availability", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "setup", default_currency: "MYR") }
  let(:user) { create(:user, account: account) }
  let(:role) { create(:role, account: account) }
  let!(:room) { create(:room_type, hotel: hotel, name: "Deluxe King", quantity: 2, max_adults: 2, base_price: 0) }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
    Onboarding::InitializeProgress.new(hotel: hotel, actor: user).call
    %w[property_profile roles_permissions staff_setup taxes_fees room_revenue rooms].each do |key|
      hotel.onboarding_sections.find_by!(section_key: key).update!(state: "complete")
    end
  end

  def per_pax_hotel
    pax_hotel = create(:hotel, :per_person, account: account, status: "setup")
    create(:user_hotel_access, user: user, hotel: pax_hotel, role: role)
    Onboarding::InitializeProgress.new(hotel: pax_hotel, actor: user).call
    %w[property_profile roles_permissions staff_setup taxes_fees room_revenue rooms].each do |key|
      pax_hotel.onboarding_sections.find_by!(section_key: key).update!(state: "complete")
    end
    pax_hotel
  end

  it "prices every rate plan in one grouped table rather than an accordion" do
    custom = create(:rate_plan, :custom, hotel: hotel, name: "Advance Purchase")
    RatePlans::BootstrapAssignment.call!(rate_plan: custom, room_type: room)

    get hotel_onboarding_section_path(hotel, section_key: "rates_availability")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Standard Rate", "Advance Purchase", "Currency · MYR")

    body = response.parsed_body
    expect(body.at_css("#onboarding-rate-plans")).to be_nil

    groups = body.css("tr.panel-record-table__group")
    expect(groups.size).to be >= 2

    # Standard covers every category by construction, so it offers no removal
    # and no room selection of its own.
    expect(groups.first.css("button[aria-label^='Remove']")).to be_empty
    expect(groups.first.text).to include("Standard Rate")

    # A custom plan heading carries only what belongs to the plan: its name and
    # how it gets its prices. Rooms are not attached from here.
    custom_heading = groups.find { |group| group.css("input[name$='[name]']").any? }
    expect(custom_heading.css("input[name$='[name]']")).not_to be_empty
    expect(custom_heading.css("select[name$='[rate_mode]']")).not_to be_empty
    expect(custom_heading.css("select[name*='room_type_id']")).to be_empty
    expect(body.css("[data-record-table-group-param]")).to be_empty
  end

  it "drops the maintenance surfaces that only matter once the property is live" do
    get hotel_onboarding_section_path(hotel, section_key: "rates_availability")

    expect(response.body).not_to include("Configured coverage", "Sellable coverage")
    expect(response.body).not_to include("Date exceptions", "Extend another year")
  end

  it "asks a per-room property for a base rate and an extra adult charge, and no child bands" do
    get hotel_onboarding_section_path(hotel, section_key: "rates_availability")

    expect(response.body).to include("Base occupancy", "Base rate", "Extra adult")
    expect(response.body).not_to include("Child age bands")
    expect(response.parsed_body.css("input[name^='child_bands']")).to be_empty
  end

  it "asks a per-pax property for occupancy prices and one property-wide child band set" do
    pax_hotel = per_pax_hotel
    pax_room = create(:room_type, hotel: pax_hotel, quantity: 1, max_adults: 3)

    get hotel_onboarding_section_path(pax_hotel, section_key: "rates_availability")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("1 adult", "2 adults", "3 adults", pax_room.name)
    expect(response.body).to include("Child age bands")
    expect(response.body).not_to include("Extra guest", "Extra adult")

    # The band section defines who a child is; what they cost is a column per
    # room on each plan, so the section itself carries no price field.
    bands_section = response.parsed_body.css("[data-controller='onboarding-child-bands']")
    expect(bands_section.css("input[name*='[label]']")).not_to be_empty
    expect(bands_section.css("input[name*='price']")).to be_empty
    expect(response.parsed_body.css("input[name*='[age_band_prices]']")).not_to be_empty

    # The adult columns already price a lone guest, so a supplement on top of
    # them could only ever be ignored — NightlyPaxPrice skips it whenever an
    # occupancy matrix exists, and onboarding always saves a complete one.
    expect(response.body).not_to include("Single supplement")
    expect(response.parsed_body.css("input[name*='single_supplement']")).to be_empty
  end

  # The form and the save path were rebuilt separately, so assert the contract
  # between them rather than each side's idea of it: submit the field names the
  # page actually renders, and expect the section to complete.
  describe "round trip" do
    def submitted_params(body, overrides: {})
      form = body.at_css("#onboarding-rates-availability-form")
      pairs = form.css("input, select").filter_map do |field|
        name = field["name"]
        next if name.blank? || field.key?("disabled")
        next if field["type"] == "checkbox" && !field.key?("checked")
        next if field["type"] == "submit"
        # Clone sources are inert in a browser and never submit.
        next if field.ancestors("template").any?

        value = if field.name == "select"
          (field.at_css("option[selected]") || field.at_css("option"))&.[]("value").to_s
        else
          field["value"].to_s
        end
        _, replacement = overrides.find { |pattern, _| name.match?(pattern) }
        [ name, replacement || value ]
      end

      Rack::Utils.parse_nested_query(pairs.map { |name, value| "#{CGI.escape(name)}=#{CGI.escape(value)}" }.join("&"))
    end

    it "completes the section from the fields the page renders, blank plan template and all" do
      get hotel_onboarding_section_path(hotel, section_key: "rates_availability")
      payload = submitted_params(response.parsed_body, overrides: {
        /\[default_rate\]/ => "180",
        /\[quantity\]/ => "2"
      })

      expect(payload).to include("standard_entries", "availability_entries", "weekend_uplift")

      patch hotel_onboarding_section_path(hotel, section_key: "rates_availability"),
            params: payload.merge("navigation_action" => "save_continue")

      expect(response).to have_http_status(:redirect)
      expect(hotel.onboarding_sections.find_by!(section_key: "rates_availability").state).to eq("complete")
      expect(room.reload.base_price).to eq(180)

      # The clone source submits blank when JS is off; it must not become a plan.
      expect(hotel.rate_plans.where(kind: "custom")).to be_empty
    end

    it "carries the per-pax occupancy prices and child bands the page renders" do
      pax_hotel = per_pax_hotel
      pax_room = create(:room_type, hotel: pax_hotel, quantity: 2, max_adults: 2, base_price: 0)

      get hotel_onboarding_section_path(pax_hotel, section_key: "rates_availability")
      payload = submitted_params(response.parsed_body, overrides: {
        /\[prices\]\[1\]/ => "100",
        /\[prices\]\[2\]/ => "180",
        /child_bands\[\d+\]\[price_value\]/ => "50",
        /\[quantity\]/ => "2"
      })

      expect(payload["child_bands"].values.map { |band| band["max_age"] }).to eq(%w[2 12])

      patch hotel_onboarding_section_path(pax_hotel, section_key: "rates_availability"),
            params: payload.merge("navigation_action" => "save_continue")

      expect(response).to have_http_status(:redirect)
      expect(pax_hotel.onboarding_sections.find_by!(section_key: "rates_availability").state).to eq("complete")

      bands = pax_room.reload.standard_rate_plan.rate_plan_age_bands
      expect(bands.map { |band| [ band.min_age, band.max_age, band.pricing_mode ] })
        .to eq([ [ 0, 2, "amount" ], [ 3, 12, "amount" ] ])
    end
  end

  # The screenshot bug: Standard rows are not removable, and omitting their
  # control cell slid every price under the wrong occupancy header.
  it "lines every price cell up under its own column header" do
    pax_hotel = per_pax_hotel
    create(:room_type, hotel: pax_hotel, name: "Pool Villa", quantity: 1, max_adults: 2)
    create(:room_type, hotel: pax_hotel, name: "Spa Villa", quantity: 1, max_adults: 4)
    custom = create(:rate_plan, :custom, hotel: pax_hotel, name: "Advance Purchase")
    RatePlans::BootstrapAssignment.call!(rate_plan: custom, room_type: pax_hotel.room_types.first)

    get hotel_onboarding_section_path(pax_hotel, section_key: "rates_availability")

    table = response.parsed_body.at_css("table.panel-record-table--rates")
    header_count = table.css("thead th").size
    # remove + room category + 4 occupancy columns + 2 required child bands
    expect(header_count).to eq(8)
    expect(table.css("thead th").map(&:text)).to include("Infant", "Child")
    expect(table.css("thead th").map(&:text)).not_to include("Teen")

    table.css("tr.panel-record-table__row").each do |row|
      expect(row.css("> td").size).to eq(header_count)
    end

    # A heading spans the same width: its own control cell plus the label.
    table.css("tr.panel-record-table__group").each do |group|
      spanned = group.css("> td").sum { |cell| (cell["colspan"] || 1).to_i }
      expect(spanned).to eq(header_count)
    end
  end

  it "dashes the occupancy cells a room cannot hold rather than offering an unusable field" do
    pax_hotel = per_pax_hotel
    create(:room_type, hotel: pax_hotel, name: "Twin", quantity: 1, max_adults: 2)
    create(:room_type, hotel: pax_hotel, name: "Family", quantity: 1, max_adults: 4)

    get hotel_onboarding_section_path(pax_hotel, section_key: "rates_availability")

    body = response.parsed_body
    twin = body.css("tr.panel-record-table__row").find { |row| row.text.include?("Twin") }
    expect(twin.text).to include("—")
    expect(twin.css("input[name*='[prices][3]']")).to be_empty
    expect(twin.css("input[name*='[prices][2]']")).not_to be_empty
  end
end
