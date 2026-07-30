require "rails_helper"

RSpec.describe "Hotel boat slot editing", type: :system, js: true do
  let(:hotel) { create(:hotel, status: "approved", allow_boat_information: true) }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account, slug: "hotel_owner", name: "Hotel Owner") }
  let!(:slot) { create(:hotel_boat_schedule, hotel: hotel, kind: "boat_in", time: "09:30", has_lunch: true) }

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

  def row = find("li:has(#boat-slot-#{slot.id})")
  def save_button = row.find("[data-boat-slot-target='save']", visible: :all)
  def discard_button = row.find("[data-boat-slot-target='discard']", visible: :all)
  def lunch_checkbox = row.find("input[type='checkbox'][name*='has_lunch']", visible: :all)

  it "reveals Save and Discard only while the row differs from what was saved" do
    expect(save_button).not_to be_visible
    expect(discard_button).not_to be_visible

    lunch_checkbox.set(false)

    expect(save_button).to be_visible
    expect(discard_button).to be_visible

    # Undoing the change by hand puts the row back to clean -- dirty is a
    # comparison against the saved values, not a latch.
    lunch_checkbox.set(true)

    expect(save_button).not_to be_visible
    expect(discard_button).not_to be_visible
  end

  it "restores the saved values and hides both buttons when Discard is clicked" do
    lunch_checkbox.set(false)
    expect(discard_button).to be_visible

    discard_button.click

    expect(discard_button).not_to be_visible
    expect(save_button).not_to be_visible
    expect(lunch_checkbox).to be_checked
    expect(slot.reload.has_lunch).to be(true)
  end

  it "keeps Retire reachable and correctly shaped while the Save pair is hidden" do
    retire = row.find("button[form='boat-slot-#{slot.id}-state']")

    expect(retire).to be_visible
    # The hidden Save pair would otherwise leave Retire with a squared leading
    # edge joined to nothing.
    radius = page.evaluate_script(<<~JS)
      getComputedStyle(document.querySelector("button[form='boat-slot-#{slot.id}-state']")).borderStartStartRadius
    JS
    expect(radius).not_to eq("0px")
  end
end
