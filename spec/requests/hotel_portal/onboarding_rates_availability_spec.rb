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
    %w[property_profile property_photos team_setup taxes_fees room_revenue rooms].each do |key|
      hotel.onboarding_sections.find_by!(section_key: key).update!(state: "complete")
    end
  end

  def per_pax_hotel
    pax_hotel = create(:hotel, :per_person, account: account, status: "setup")
    create(:user_hotel_access, user: user, hotel: pax_hotel, role: role)
    Onboarding::InitializeProgress.new(hotel: pax_hotel, actor: user).call
    %w[property_profile property_photos team_setup taxes_fees room_revenue rooms].each do |key|
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

    # The shell heads the step; the partial opens on its peer groups, not on a
    # second statement of the same subject.
    expect(body.css("h1").map { |heading| heading.text.strip }).to eq([ "Rates and availability" ])
    expect(body.css("div.overflow-y-auto h2").map { |heading| heading.text.strip })
      .to eq([ "Rate plans", "Availability" ])

    groups = body.css("tr.panel-record-table__group")
    expect(groups.size).to be >= 2

    # Standard covers every category by construction, so it offers no removal
    # and no room selection of its own.
    expect(groups.first.css("button[aria-label^='Remove']")).to be_empty
    expect(groups.first.text).to include("Standard Rate")

    # A custom plan heading carries what belongs to the plan: its name and how
    # it gets its prices. Coverage is decided on the rows, so the heading offers
    # no room picker of its own.
    custom_heading = groups.find { |group| group.css("input[name$='[name]']").any? }
    expect(custom_heading.css("input[name$='[name]']")).not_to be_empty
    expect(custom_heading.css("select[name$='[rate_mode]']")).not_to be_empty
    expect(custom_heading.css("select[name*='room_type_id']")).to be_empty
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
    expect(response.parsed_body.css("div.overflow-y-auto h2").map { |heading| heading.text.strip })
      .to eq([ "Child age bands", "Rate plans", "Availability" ])

    # The band section defines who a child is; what they cost is a column per
    # room on each plan, so the section itself carries no price field.
    bands_section = response.parsed_body.css("[data-controller='onboarding-child-bands']")
    expect(bands_section.css("input[name*='[label]']")).not_to be_empty
    expect(bands_section.css("input[name*='price']")).to be_empty
    expect(response.parsed_body.css("input[name*='[age_band_prices]']")).not_to be_empty
    mode_switches = response.parsed_body.css("th .panel-switch[data-variant='icon'][data-size='md'] input[role='switch']")
    expect(mode_switches.size).to eq(2)
    expect(mode_switches.map { |input| input["name"] }).to eq(
      %w[child_bands[0][pricing_mode] child_bands[1][pricing_mode]]
    )

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
    header_text = table.css("thead th").map { |header| header.text.squish }
    expect(header_text).to include(a_string_starting_with("Infant"), a_string_starting_with("Child"))
    expect(header_text).not_to include(a_string_starting_with("Teen"))
    expect(table.css("thead th > .flex.items-center").size).to eq(2)

    table.css("tr.panel-record-table__row").each do |row|
      expect(row.css("> td").size).to eq(header_count)
    end

    # A heading spans the same width: its own control cell plus the label.
    table.css("tr.panel-record-table__group").each do |group|
      spanned = group.css("> td").sum { |cell| (cell["colspan"] || 1).to_i }
      expect(spanned).to eq(header_count)
    end
  end

  # A plan that should not sell every category — Corporate on suites only — is
  # expressed by dropping its rows, so each custom row carries removal and the
  # plan carries a row that asks which category to add back.
  it "lets a custom plan drop a room category and add one back through a picker" do
    custom = create(:rate_plan, :custom, hotel: hotel, name: "Advance Purchase")
    RatePlans::BootstrapAssignment.call!(rate_plan: custom, room_type: room)
    create(:room_type, hotel: hotel, name: "Pool Villa", quantity: 1, max_adults: 2)

    get hotel_onboarding_section_path(hotel, section_key: "rates_availability")

    body = response.parsed_body
    rows = body.css("tr.panel-record-table__row")
    custom_rows = rows.select { |row| row.css("input[name^='custom_plans[plan-#{custom.id}]']").any? }
    expect(custom_rows.size).to eq(2)

    custom_rows.each do |row|
      expect(row["data-record-table-soft"]).to eq("true")
      expect(row.css("input[data-record-table-destroy][value='0']")).not_to be_empty
      expect(row.css("button[aria-label^='Remove']").map { |button| button["aria-label"] })
        .to all(end_with("from Advance Purchase"))
    end

    # Standard has no coverage decision to make, so its rows keep neither.
    standard_rows = rows.select { |row| row.css("input[name^='standard_entries']").any? }
    expect(standard_rows.flat_map { |row| row.css("input[data-record-table-destroy]").to_a }).to be_empty

    heading = body.css("tr.panel-record-table__group").find do |group|
      group.css("input[name^='custom_plans[plan-#{custom.id}]']").any?
    end
    expect(heading.css("[data-record-table-group-param='plan-#{custom.id}']").text.squish).to eq("Room")

    # The row that button adds asks which category, rather than the heading
    # listing every category the plan already sells.
    picker = body.css("template[data-record-table-group='plan-#{custom.id}']").sole
    choices = picker.css("select[name$='[room_type_id]'] option").map { |option| option.text.squish }
    expect(choices).to include("Deluxe King", "Pool Villa")
    # Its cells still line up with the columns the chosen room will fill.
    expect(picker.css("tr.panel-record-table__row > td").size)
      .to eq(body.at_css("table.panel-record-table--rates thead").css("th").size)
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

    # A cell nobody has priced yet shows the zero it already means to the save
    # path, rather than reading as a field that failed to load.
    expect(twin.css("input[name*='[prices][2]'], input[name*='[age_band_prices]']").map { |cell| cell["value"] })
      .to all(eq("0.0"))
  end
end
