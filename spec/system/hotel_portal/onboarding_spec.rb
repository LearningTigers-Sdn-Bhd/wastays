# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel onboarding shell", type: :system do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "setup") }
  let(:user) { create(:user, account: account) }
  let(:role) { create(:role, account: account) }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as_system(user)
  end

  def reach_commercial_phase!
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    Onboarding::InitializeProgress.new(hotel: hotel).call
    keys = Onboarding::SectionCatalog.keys
    keys[0..keys.index("rates_availability")].each do |key|
      hotel.onboarding_sections.find_by!(section_key: key).update!(state: "complete")
    end
  end

  it "offers compact progress details on a narrow screen" do
    page.current_window.resize_to(390, 844)

    visit hotel_onboarding_path(hotel)

    expect(page).to have_css("details summary", text: "Property · Phase 1 of 6")
    find("details summary").click
    expect(page).to have_css("details[open]", text: "Rooms & rates")
    expect(page).to have_css("details[open]", text: "Locked")
  end

  it "resumes setup and advances through a completed property profile" do
    hotel.update!(
      contact_email: "stay@example.com",
      contact_phone: "+60312345678",
      time_zone: "Kuala Lumpur"
    )
    hotel.create_property_policy!(check_in_time: "15:00", check_out_time: "11:00")
    hotel.photos.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/sample_image.jpg")),
      filename: "property.jpg",
      content_type: "image/jpeg"
    )
    hotel.update!(featured_photo_attachment_id: hotel.photos.attachments.last.id)

    visit hotel_onboarding_path(hotel)

    expect(page).to have_css("h1", text: "Property profile")
    expect(page).to have_css("nav[aria-label='Onboarding progress']")
    expect(page).to have_button("Save & continue")

    click_button "Save & continue"

    expect(page).to have_current_path(hotel_onboarding_section_path(hotel, section_key: "roles_permissions"))
    expect(page).to have_css("h1", text: "Roles and permissions")
    expect(page).to have_link("Back", href: hotel_onboarding_section_path(hotel, section_key: "property_profile"))

    check "I reviewed the Hotel Owner, General Manager, Front Desk, and Housekeeper presets"
    click_button "Save & continue"

    expect(page).to have_current_path(hotel_onboarding_section_path(hotel, section_key: "staff_setup"))
    expect(page).to have_text("Nothing is sent now")
    # Nobody else needs access yet, and the empty table says so: continuing from
    # it is the decision, with no separate skip button to press.
    expect(page).to have_text("No staff added yet")
    click_button "Save & continue"

    expect(page).to have_current_path(hotel_onboarding_section_path(hotel, section_key: "taxes_fees"))
    expect(hotel.onboarding_sections.find_by!(section_key: "staff_setup").state).to eq("skipped")

    expect(page).to have_css("h1", text: "Taxes and fees")
    check "I confirm these are the taxes and fees this property charges"
    click_button "Save & continue"

    expect(page).to have_current_path(hotel_onboarding_section_path(hotel, section_key: "room_revenue"))
    expect(page).to have_css("h1", text: "Room revenue")
    expect(page).to have_text("Posting preview")

    click_button "Save & continue"

    expect(page).to have_current_path(hotel_onboarding_section_path(hotel, section_key: "rooms"))
    expect(hotel.onboarding_sections.find_by!(section_key: "room_revenue").state).to eq("complete")
    expect(hotel.hotel_reservation_policies.count).to eq(4)
  end

  it "adds and removes records in an editable table" do
    Onboarding::InitializeProgress.new(hotel: hotel).call
    hotel.onboarding_sections.find_by!(section_key: "property_profile").update!(state: "complete")
    # The preset roles the staff rows choose from are created by this step, so
    # run it rather than only marking its section complete.
    Onboarding::ConfirmRolePresets.new(hotel: hotel, actor: user, confirmed: true).call

    visit hotel_onboarding_section_path(hotel, section_key: "staff_setup")

    # The page opens on the empty state, which carries the add action itself. The
    # footer's copy of it stands down while that is showing.
    expect(page).to have_no_css("tr[data-record-table-target='row']")
    expect(page).to have_css("tr.panel-record-table__empty", text: "No staff added yet")
    expect(page).to have_css("button", text: "Add staff member", count: 1)

    click_button "Add staff member"

    expect(page).to have_css("tr[data-record-table-target='row']", count: 1)
    expect(page).to have_no_css("tr.panel-record-table__empty")
    # Focus lands on the first field, not on the remove button that precedes it.
    expect(page.evaluate_script("document.activeElement.name")).to end_with("[name]")

    click_button "Add staff member"
    expect(page).to have_css("tr[data-record-table-target='row']", count: 2)

    all("button[aria-label='Remove this staff member']").each(&:click)

    expect(page).to have_no_css("tr[data-record-table-target='row']")
    expect(page).to have_css("tr.panel-record-table__empty", text: "No staff added yet")
  end

  it "configures rooms in the spreadsheet and stages amenities and numbering in one sheet" do
    Onboarding::InitializeProgress.new(hotel: hotel).call
    %w[property_profile roles_permissions staff_setup taxes_fees room_revenue].each do |key|
      hotel.onboarding_sections.find_by!(section_key: key).update!(state: "complete")
    end
    amenity = Hotel::CATEGORIZED_ROOM_AMENITIES.first[:items].first
    amenity_label = "#{Hotel::CATEGORIZED_ROOM_AMENITIES.first[:category]} · #{amenity[:name]}"

    visit hotel_onboarding_section_path(hotel, section_key: "rooms")

    expect(page).to have_css("tr[data-record-table-target='row']", count: 1)
    fill_in "Room category", with: "Deluxe Twin"
    fill_in "Max adults for this room category", with: "2"
    fill_in "Max children for this room category", with: "1"
    fill_in "Total rooms for this room category", with: "2"
    check "No smoking in this room category"
    check "No pets in this room category"

    find("button[aria-label='Manage amenities for this room category']").click
    expect(page).to have_css("dialog#onboarding_action_sheet[open]")
    amenity_picker = find("[data-onboarding-room-grid-target='amenityPicker']")
    amenity_picker.find(".ts-control").click
    amenity_picker.find(".ts-dropdown .option", text: amenity_label).click
    click_button "Apply"
    expect(page).to have_css("button[aria-label='Manage amenities for this room category']", text: "1 amenities")

    find("button[aria-label='Manage room numbering for this room category']").click
    choose "Sequential numbers"
    fill_in "Starting number", with: "101"
    expect(page).to have_css("[data-size='xs']", text: "101")
    expect(page).to have_css("[data-size='xs']", text: "102")
    click_button "Apply"
    room_row = find("tr[data-record-table-target='row']")
    expect(room_row).to have_css("[data-room-number-badges] [data-size='xs']", text: "101")
    expect(room_row).to have_css("[data-room-number-badges] [data-size='xs']", text: "102")
    expect(room_row.find("td:last-child").text).to eq("Manage room numbering")

    click_button "Save & continue"

    expect(page).to have_current_path(hotel_onboarding_section_path(hotel, section_key: "rates_availability"))
    room = hotel.room_types.sole
    expect(room).to have_attributes(name: "Deluxe Twin", quantity: 2, base_price: 0.to_d)
    expect(room.room_numbers).to eq([ "101", "102" ])
    expect(room.amenities).to eq([ amenity[:id].to_s ])
  end

  # Coverage is edited on the rows: a category comes off a plan by removing its
  # row, and "+ Room" adds a row that asks which category to put back.
  it "takes a room category off a custom rate plan and puts it back" do
    suite = create(:room_type, hotel: hotel, name: "Suite", quantity: 1, max_adults: 2, base_price: 200)
    create(:room_type, hotel: hotel, name: "Deluxe", quantity: 1, max_adults: 2, base_price: 150)
    Onboarding::InitializeProgress.new(hotel: hotel, actor: user).call
    %w[property_profile roles_permissions staff_setup taxes_fees room_revenue rooms].each do |key|
      hotel.onboarding_sections.find_by!(section_key: key).update!(state: "complete")
    end
    plan = create(:rate_plan, :custom, hotel: hotel, name: "Corporate")
    hotel.room_types.each { |type| RatePlans::BootstrapAssignment.call!(rate_plan: plan, room_type: type) }

    visit hotel_onboarding_section_path(hotel, section_key: "rates_availability")

    # The clone source for "Add rate plan" carries the same row keys, so wait for
    # the controller to lift it out before addressing a row by its category.
    expect(page).to have_css("tr[data-record-table-key='assignment-#{suite.id}']", count: 1)
    plan_heading = all("tr.panel-record-table__group").find { |row| row.has_field?("Rate plan name", with: "Corporate") }
    deluxe_row = find("tr[data-record-table-key='assignment-#{hotel.room_types.find_by!(name: 'Deluxe').id}']")

    # Nothing to add while the plan sells everything.
    expect(plan_heading).not_to have_button("Room")

    deluxe_row.find("button[aria-label='Remove Deluxe from Corporate']").click

    expect(deluxe_row).not_to be_visible
    expect(plan_heading).to have_button("Room")

    # The last category standing cannot be removed: a plan that prices nothing
    # is not a plan, and removing it is the control one row up.
    suite_row = find("tr[data-record-table-key='assignment-#{suite.id}']")
    expect(suite_row.find("button[aria-label='Remove Suite from Corporate']")).to be_disabled

    plan_heading.click_button("Room")

    # The picker offers what the plan is missing and nothing it already sells,
    # so a property with thirty categories reads the same as one with two.
    expect(all("tr.panel-record-table__row [role='option']", visible: :all).map { |option| option.text(:all) })
      .to contain_exactly("Deluxe")

    find("tr.panel-record-table__row .panel-select-menu__trigger").click
    find("tr.panel-record-table__row [role='option']", text: "Deluxe").click

    expect(deluxe_row).to be_visible
    expect(page).to have_no_css("select[name*='room_picker']", visible: :all)
    expect(plan_heading).not_to have_button("Room")
  end

  # The screenshot bug: the per-pax table pins its first two columns, and the
  # heading's spanning cell was pinned with them — squeezing the plan's name,
  # basis and adjustment into a column-wide stack.
  it "lays a rate plan heading across the pinned columns rather than inside them" do
    pax_hotel = create(:hotel, :per_person, account: account, status: "setup")
    create(:user_hotel_access, user: user, hotel: pax_hotel, role: role)
    create(:room_type, hotel: pax_hotel, name: "Suite", quantity: 1, max_adults: 4, base_price: 200)
    Onboarding::InitializeProgress.new(hotel: pax_hotel, actor: user).call
    %w[property_profile roles_permissions staff_setup taxes_fees room_revenue rooms].each do |key|
      pax_hotel.onboarding_sections.find_by!(section_key: key).update!(state: "complete")
    end
    plan = create(:rate_plan, :custom, hotel: pax_hotel, name: "Corporate")
    RatePlans::BootstrapAssignment.call!(rate_plan: plan, room_type: pax_hotel.room_types.sole)

    visit hotel_onboarding_section_path(pax_hotel, section_key: "rates_availability")
    expect(page).to have_field("Rate plan name", with: "Corporate")

    layout = page.evaluate_script(<<~JS)
      (() => {
        const name = document.querySelector("input[name$='[name]'][placeholder='Rate plan name']")
        const content = name.closest(".panel-record-table__group-content")
        const adjust = content.querySelector("input[name$='[derive_value]']")
        const column = document.querySelector(".panel-record-table--rates tbody tr.panel-record-table__row > :nth-child(2)")
        return {
          width: content.getBoundingClientRect().width,
          column: column.getBoundingClientRect().width,
          sameLine: Math.round(name.getBoundingClientRect().top) === Math.round(adjust.getBoundingClientRect().top)
        }
      })()
    JS

    expect(layout["width"]).to be > layout["column"]
    expect(layout["sameLine"]).to be(true)
  end

  # An owner naming what the property sells should not have to answer for an
  # accounting code, a pricing method or an override rule to do it.
  it "adds an extra charge from a name alone" do
    reach_commercial_phase!

    visit hotel_onboarding_section_path(hotel, section_key: "extra_charges")
    click_button "Add extra charge"
    all("input[placeholder='Airport transfer']").last.set("Airport transfer")
    click_button "Save & continue"

    expect(page).to have_css("h1", text: "Discounts")
    expect(hotel.hotel_extra_charges.find_by!(transaction_code: hotel.transaction_codes.find_by(name: "Airport transfer")))
      .to have_attributes(code: "AIRPORT_TR", pricing_type: "manual", charging_unit: "per_item")
  end

  # The page is headed once, by the shell, and the columns that need explaining
  # explain themselves from their own headers rather than in prose above.
  it "explains the extra charge columns from their headers, and heads the page once" do
    reach_commercial_phase!

    visit hotel_onboarding_section_path(hotel, section_key: "extra_charges")

    expect(page).to have_css("h1", text: "Extra charges")
    expect(page).to have_no_css("h2", text: "What else can guests buy?")
    expect(page).to have_css("button[aria-label^='Price (MYR): Leave it empty']")

    find("button[aria-label='About Charged']").hover

    expect(page).to have_text("For each room, every night")
  end

  # An owner naming the offers a property makes should not have to answer for an
  # accounting code, an override rule or a reporting status to do it.
  it "adds a discount from a name alone" do
    reach_commercial_phase!

    visit hotel_onboarding_section_path(hotel, section_key: "extra_charges")
    click_button "No extra charges for now"

    expect(page).to have_css("h1", text: "Discounts")
    click_button "Add discount"
    all("input[placeholder='Early bird']").last.set("Early bird")
    click_button "Save & continue"

    expect(page).to have_css("h1", text: "Payment methods")
    expect(hotel.hotel_discounts.find_by!(transaction_code: hotel.transaction_codes.find_by(name: "Early bird")))
      .to have_attributes(code: "EARLY_BIRD", pricing_type: "manual", application_scope: "all_eligible_charges")
  end

  # Two pairs of controls share a cell, which is what keeps the table at three
  # columns. In each pair the second control only means anything under one value
  # of the first, so it appears with that value rather than sitting dead beside
  # it — and the page is headed once, by the shell.
  it "reveals a discount's amount and its charge picker only where they apply" do
    reach_commercial_phase!

    visit hotel_onboarding_section_path(hotel, section_key: "extra_charges")
    click_button "No extra charges for now"

    expect(page).to have_css("h1", text: "Discounts")
    expect(page).to have_no_css("h2", text: "What can reduce a guest's bill?")

    row = first("tr.panel-record-table__row")

    # Staff-priced by default: there is no amount to type at all.
    expect(row).to have_no_css("[data-discount-row-target='rateField']")
    expect(row).to have_no_css("[data-discount-row-target='codesField']")

    within(row) do
      find("[data-discount-row-target='typeField'] .panel-select-menu__trigger").click
      find("[role='option']", text: "Percentage").click
    end

    # The percent sign trails the rate; the currency mark that would lead a fixed
    # amount stays out of the way.
    expect(row).to have_css("[data-discount-row-target='percentAddon']", text: "%")
    expect(row).to have_no_css("[data-discount-row-target='currencyAddon']")

    within(row) do
      find("[data-discount-row-target='scope'] .panel-select-menu__trigger").click
      find("[role='option']", text: "Only the charges I choose").click
    end

    expect(row).to have_css("[data-discount-row-target='codesField']")
    expect(row).to have_css("[data-discount-row-target='codesField'] select:not(:disabled)", visible: :all)
    expect(row).to have_css("[data-discount-row-target='codesField'] .ts-control")
    expect(row).to have_no_css("[data-discount-row-target='codesField'] .ts-wrapper.disabled")
  end

  # The commercial phase's owner path: one way to take money is required, the
  # other three sections are answered rather than left silent.
  it "takes an owner through the commercial phase" do
    reach_commercial_phase!

    visit hotel_onboarding_section_path(hotel, section_key: "extra_charges")

    expect(page).to have_css("h1", text: "Extra charges")
    expect(page).to have_text("These are suggestions, not saved yet")
    click_button "No extra charges for now"

    expect(page).to have_css("h1", text: "Discounts")
    click_button "No discounts for now"

    expect(page).to have_css("h1", text: "Payment methods")
    # Required: no skip is offered here at all.
    expect(page).to have_no_button("No payment methods for now")
    # Headed once, by the shell, and asking two things: a surcharge is a fee
    # decision the property makes under Settings. The standard codes read as
    # text and say, where their remove control would be, why they stay.
    expect(page).to have_no_css("h2", text: "How can guests pay?")
    expect(page).to have_no_css("th", text: "Surcharge")
    expect(page).to have_css("tr.panel-record-table__row", text: "Cash Payment")
    expect(page).to have_no_css("button[aria-label='Remove Cash Payment']")
    expect(page).to have_css("button[aria-label^='A standard payment code']")
    click_button "Save & continue"

    expect(page).to have_css("h1", text: "Corporate accounts")
    expect(page).to have_text("No invitations are sent yet")
    expect(page).to have_text("No corporate accounts yet")
    click_button "Save & continue"

    expect(page).to have_css("h1", text: "Channel manager")
    expect(hotel.hotel_payment_methods.active).to be_present
    expect(Invitation.count).to eq(0)
  end
end
