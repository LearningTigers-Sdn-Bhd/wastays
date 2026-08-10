require "rails_helper"

RSpec.describe "Hotel inventory calendar", type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin", email: "inventory@example.com") }
  let(:hotel) { create(:hotel, account: account, status: "approved", default_currency: "MYR") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let!(:room_type) { create(:room_type, hotel: hotel, name: "Twin Room", quantity: 4, base_price: 180, room_numbers: %w[201 202 203 204]) }
  let!(:rate_plan) { create(:rate_plan, room_type: room_type, name: "Best Available Rate") }

  before do |example|
    driven_by(example.metadata[:js] ? :cuprite : :rack_test)

    [
      "manage_guest_arrival", "view_bookings", "manage_room_status", "manage_requests",
      "manage_hotel_profile", "manage_users", "view_reports", "view_payouts", "view_audit_logs",
      "manage_night_audit"
    ].each do |slug|
      permission = Permission.find_by(slug: slug) || create(:permission, name: slug.titleize, slug: slug)
      role.permissions << permission unless role.permissions.include?(permission)
    end

    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
  end

  it "renders the PMS calendar views and persisted ARI values" do
    create(:room_inventory, room_type: room_type, date: Date.current, quantity: 2, status: "open")
    create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.current, price: 333, currency: "MYR", min_stay: 2, stop_sell: true)

    visit hotel_inventory_index_path(hotel, start_date: Date.current)
    expect(page).to have_content("Rates & Availability")
    expect(page).to have_css("[data-testid='availability-cell-#{room_type.id}-#{Date.current}']", text: "2")
    expect(page).to have_css("[data-testid='rate-cell-#{room_type.id}-#{rate_plan.id}-#{Date.current}']", text: "333.00")
    expect(page).to have_css("[data-testid='rate-cell-#{room_type.id}-#{rate_plan.id}-#{Date.current}']", text: "MIN2")
    expect(page).to have_css("[data-testid='rate-cell-#{room_type.id}-#{rate_plan.id}-#{Date.current}']", text: "STOP")
  end

  # The editor is a plain link into a frame, so it opens without JavaScript.
  it "opens the cell editor from the calendar" do
    create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.current, price: 333, currency: "MYR")

    visit hotel_inventory_index_path(hotel, start_date: Date.current)
    find("[data-testid='rate-cell-#{room_type.id}-#{rate_plan.id}-#{Date.current}']").click

    expect(page).to have_content("Update rates")
    expect(page).to have_field("selection_update[price]", with: "333.0")
    expect(page).to have_button("Stage update")
  end

  it "switches room context, stages its plans, and highlights the affected cells", :js do
    garden_suite = create(:room_type, hotel: hotel, name: "Garden Suite", quantity: 2, base_price: 280)
    garden_standard = garden_suite.rate_plans.active.order(:id).first
    garden_member = create(:rate_plan, :custom, room_type: garden_suite, name: "Garden Member")
    create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.current, price: 333, currency: "MYR")
    create(:room_rate, room_type: garden_suite, rate_plan: garden_standard, date: Date.current, price: 444, currency: "MYR")

    visit hotel_inventory_index_path(hotel, start_date: Date.current)
    find("[data-testid='rate-cell-#{room_type.id}-#{rate_plan.id}-#{Date.current}']").click

    expect(page).to have_select("Room category", selected: "Twin Room")
    expect(page).not_to have_css("select[name='selection_update[room_type_ids][]']", visible: :all)

    fill_in "Room price (MYR)", with: "399"
    dismiss_confirm do
      find("select[name='selection_update[room_type_context_id]'] option[value='#{garden_suite.id}']", visible: :all).select_option
    end
    expect(page).to have_css("form[data-room-type-id='#{room_type.id}']")
    expect(page).to have_field("selection_update[price]", with: "399")
    fill_in "Room price (MYR)", with: "333.0"

    find("select[name='selection_update[room_type_context_id]'] option[value='#{garden_suite.id}']", visible: :all).select_option

    expect(page).to have_css("form[data-room-type-id='#{garden_suite.id}']")
    expect(page).to have_select("Room category", selected: "Garden Suite")
    expect(page).to have_field("selection_update[price]", with: "444.0")
    expect(page).to have_css("select[name='selection_update[rate_plan_ids][]'] option[value='#{garden_standard.id}']", visible: :all)
    expect(page).to have_css("select[name='selection_update[rate_plan_ids][]'] option[value='#{garden_member.id}']", visible: :all)
    expect(page).not_to have_css("select[name='selection_update[rate_plan_ids][]'] option[value='#{rate_plan.id}']", visible: :all)

    find("select[name='selection_update[rate_plan_ids][]'] option[value='#{garden_member.id}']", visible: :all).select_option
    end_date_input = find("input[name='selection_update[end_date]']", visible: :all)
    page.execute_script(<<~JS, end_date_input, (Date.current + 1.day).iso8601)
      arguments[0].value = arguments[1]
      arguments[0].dispatchEvent(new Event("input", { bubbles: true }))
      arguments[0].dispatchEvent(new Event("change", { bubbles: true }))
    JS
    fill_in "Room price (MYR)", with: "355"
    click_button "Stage update"

    click_button "Confirm Update"
    expect(page).to have_content("Garden Suite")
    expect(page).to have_content(garden_standard.name)
    expect(page).to have_content("Garden Member")

    [ garden_standard, garden_member ].each do |plan|
      [ Date.current, Date.current + 1.day ].each do |date|
        cell = find("[data-testid='rate-cell-#{garden_suite.id}-#{plan.id}-#{date}']")
        expect(cell[:class]).to include("bg-indigo-50/70")
      end
    end
  end
end
