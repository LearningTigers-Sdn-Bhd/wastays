# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Group billing routes", type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "hotel_staff", email: "group-routes@example.com") }
  let(:hotel) { create(:hotel, account: account, status: "live") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }
  let(:group) { create(:group_booking, hotel: hotel) }

  before do |example|
    driven_by(example.metadata[:js] ? :cuprite : :rack_test)
    allow(BookingRedesign).to receive(:enabled?).and_return(true)
    %w[view_bookings manage_bookings manage_folio_movements].each do |slug|
      role.permissions << Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    end
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    visit login_path
    fill_in "Email Address", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In to Portal"
  end

  it "filters transaction code rows live across every booking and blocks apply while a sibling needs review", js: true do
    booking = create(:booking, hotel: hotel, group_booking: group, group_position: 1, reservation_number: 301)
    ready_guest = create(:booking_guest, booking: booking, is_primary: true)
    create(:booking_folio, booking: booking, hotel: hotel, is_primary: true, booking_billing_party: ready_guest.booking_billing_party)
    sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, reservation_number: 302)
    create(:booking_folio, booking: sibling, hotel: hotel, is_primary: true)
    code = create(:transaction_code, hotel: hotel, kind: "charge", code: "GRPX", name: "Group charge")

    visit hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences")
    click_button "Change Billing Routes"
    click_link "Group Billing Routes"

    expect(page).to have_css("turbo-frame#folio_action_sheet dialog#folio-group-billing-routes-sheet[open]")
    within("dialog#folio-group-billing-routes-sheet") do
      expect(page).to have_content(/change group billing routes/i)
      expect(page).to have_content(booking.formatted_reservation_number)
      expect(page).to have_content(sibling.formatted_reservation_number)
      expect(page).to have_content("No billing party assigned")

      row_selector = "tr[data-route-level='parent'][data-code-id='#{code.id}']"
      expect(page).to have_css(row_selector, visible: :hidden, count: 2)
      expect(page).to have_no_css(row_selector, visible: :visible)

      click_in_overlay find("input[type=checkbox][data-code-id='#{code.id}']")
      expect(page).to have_css("input[type=checkbox][data-code-id='#{code.id}']:checked")

      expect(page).to have_css(row_selector, visible: :visible, count: 2, wait: 5)
      expect(page).to have_button("Review & Apply", disabled: true)
    end
    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences"))
  end

  it "applies a routing change across group siblings and closes the Sheet", js: true do
    booking = create(:booking, hotel: hotel, group_booking: group, group_position: 1, reservation_number: 401)
    guest = create(:booking_guest, booking: booking, is_primary: true)
    create(:booking_folio, booking: booking, hotel: hotel, is_primary: true, booking_billing_party: guest.booking_billing_party)
    company_party = create(:booking_billing_party, :company, booking: booking, hotel: hotel)
    company_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, label: "Company Folio",
      booking_billing_party: company_party, payer_type: "company", hotel_corporate_account: company_party.hotel_corporate_account)
    sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, reservation_number: 402)
    sibling_guest = create(:booking_guest, booking: sibling, is_primary: true)
    create(:booking_folio, booking: sibling, hotel: hotel, is_primary: true, booking_billing_party: sibling_guest.booking_billing_party)
    code = create(:transaction_code, hotel: hotel, kind: "charge", code: "GRPY", name: "Group charge two")
    create(:folio_transaction, booking_folio: booking.booking_folio, transaction_code: code, amount: 75)

    visit hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences")
    click_button "Change Billing Routes"
    click_link "Group Billing Routes"

    within("dialog#folio-group-billing-routes-sheet") do
      click_in_overlay find("input[type=checkbox][data-code-id='#{code.id}']")
      expect(page).to have_css("input[type=checkbox][data-code-id='#{code.id}']:checked")

      row_selector = "tr[data-route-level='parent'][data-booking-id='#{booking.id}'][data-code-id='#{code.id}']"
      expect(page).to have_css(row_selector, visible: :visible, wait: 5)
      row = find(row_selector)
      party_select = row.find("select[name='group_routes[#{booking.id}][#{code.id}][billing_party_id]']", visible: :all)
      page.execute_script("arguments[0].value = arguments[1]; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", party_select, company_party.id.to_s)
      folio_select = row.find("select[name='group_routes[#{booking.id}][#{code.id}][target_folio_id]']", visible: :all)
      expect(folio_select).to have_css("option[value='#{company_folio.id}']", visible: :all)
      page.execute_script("arguments[0].value = arguments[1]; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", folio_select, company_folio.id.to_s)

      expect(page).to have_button("Review & Apply", disabled: false)
      click_in_overlay "Review & Apply"
    end

    within("dialog#folio-group-billing-routes-sheet") do
      expect(page).to have_content("Existing charge impact")
      click_in_overlay "Back"
    end

    within("dialog#folio-group-billing-routes-sheet") do
      click_in_overlay find("input[type=checkbox][data-code-id='#{code.id}']")
      row = find("tr[data-route-level='parent'][data-booking-id='#{booking.id}'][data-code-id='#{code.id}']", visible: :visible, wait: 5)
      party_select = row.find("select[name='group_routes[#{booking.id}][#{code.id}][billing_party_id]']", visible: :all)
      page.execute_script("arguments[0].value = arguments[1]; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", party_select, company_party.id.to_s)
      folio_select = row.find("select[name='group_routes[#{booking.id}][#{code.id}][target_folio_id]']", visible: :all)
      expect(folio_select).to have_css("option[value='#{company_folio.id}']", visible: :all)
      page.execute_script("arguments[0].value = arguments[1]; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", folio_select, company_folio.id.to_s)
      click_in_overlay "Review & Apply"
    end

    within("dialog#folio-group-billing-routes-sheet") do
      fill_in "Reason", with: "Company settles group charge"
      click_in_overlay "Confirm and apply"
    end

    expect(page).to have_no_css("dialog#folio-group-billing-routes-sheet", wait: 5)
    expect(booking.folio_routing_rules.active.find_by(transaction_code: code)&.target_folio).to eq(company_folio)
    expect(sibling.folio_routing_rules.active.where(transaction_code: code)).to be_empty
  end
end
