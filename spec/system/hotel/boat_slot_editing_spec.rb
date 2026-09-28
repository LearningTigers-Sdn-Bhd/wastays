require "rails_helper"

RSpec.describe "Hotel boat slot editing", type: :system, js: true do
  let(:hotel) { create(:hotel, status: "live", allow_boat_information: true) }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account, slug: "hotel_owner", name: "Hotel Owner") }
  let!(:slot) { create(:hotel_boat_schedule, hotel: hotel, kind: "boat_in", time: "14:00", has_lunch: true) }
  let!(:other_slot) { create(:hotel_boat_schedule, hotel: hotel, kind: "boat_out", time: "10:00") }

  before do
    driven_by(:cuprite)

    %w[manage_account manage_hotel_profile].each do |slug|
      permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.titleize }
      RolePermission.find_or_create_by!(role: role, permission: permission)
    end
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
    visit hotel_boat_settings_path(hotel)
    expect(page).to have_css("#boat-slot-#{slot.id}", wait: 10)
  end

  def row(record = slot) = find("li:has(#boat-slot-#{record.id})")
  def discard_button(record = slot) = row(record).find("[data-boat-slot-target='discard']", visible: :all)
  def lunch_checkbox = row.find("input[type='checkbox'][name*='has_lunch']", visible: :all)
  def time_display(record = slot) = row(record).find(".panel-time-picker__value").text
  def time_value(record = slot) = row(record).find("input[type='hidden'][name='hotel_boat_schedule[time]']", visible: :all).value
  def bulk_bar = find("[data-boat-slots-bulk-target='bar']", visible: :all)

  def pick_minutes(minutes, record = slot)
    row(record).find(".panel-time-picker__display").click
    find(".popover[data-state='open'] [data-time-option='minutes'][data-time-value='#{minutes}']").click
    find("h2", text: "Boat Arrival (Boat-in)").click
  end

  it "reveals Discard and the Save bar only while a row differs from what was saved" do
    expect(discard_button).not_to be_visible
    expect(bulk_bar).not_to be_visible

    lunch_checkbox.set(false)

    expect(discard_button).to be_visible
    expect(bulk_bar).to be_visible

    # Undoing the change by hand puts the row back to clean -- dirty is a
    # comparison against the saved values, not a latch.
    lunch_checkbox.set(true)

    expect(discard_button).not_to be_visible
    expect(bulk_bar).not_to be_visible
  end

  it "restores a checkbox when Discard is clicked" do
    lunch_checkbox.set(false)
    discard_button.click

    expect(discard_button).not_to be_visible
    expect(lunch_checkbox).to be_checked
    expect(slot.reload.has_lunch).to be(true)
  end

  it "restores a changed time when Discard is clicked" do
    pick_minutes(10)
    expect(time_display).to eq("14:10")
    expect(discard_button).to be_visible

    discard_button.click

    expect(time_display).to eq("14:00")
    expect(time_value).to eq("14:00")
    expect(discard_button).not_to be_visible
    expect(bulk_bar).not_to be_visible
  end

  it "restores every changed time when Discard all is clicked" do
    pick_minutes(10)
    pick_minutes(15, other_slot)
    expect(bulk_bar).to have_text("2 boat slots changed")

    within(bulk_bar) { click_button "Discard all" }

    expect(time_display).to eq("14:00")
    expect(time_display(other_slot)).to eq("10:00")
    expect(bulk_bar).not_to be_visible
  end

  it "saves every changed row in one go from the Save bar" do
    pick_minutes(10)
    lunch_checkbox.set(false)

    within(bulk_bar) { click_button "Save changes" }

    expect(page).to have_text("1 boat slot updated.")
    expect(slot.reload.time_of_day).to eq("14:10")
    expect(slot.has_lunch).to be(false)
  end

  it "keeps Retire reachable and correctly shaped while Discard is hidden" do
    retire = row.find("button[form='boat-slot-#{slot.id}-state']")

    expect(retire).to be_visible
    # The hidden Discard would otherwise leave Retire with a squared leading
    # edge joined to nothing.
    radius = page.evaluate_script(<<~JS)
      getComputedStyle(document.querySelector("button[form='boat-slot-#{slot.id}-state']")).borderStartStartRadius
    JS
    expect(radius).not_to eq("0px")
  end
end
