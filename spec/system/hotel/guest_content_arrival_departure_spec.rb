require "rails_helper"

RSpec.describe "Guest content arrival and departure settings", type: :system, js: true do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "live") }
  let(:role) { create(:role, account: account, slug: "hotel_owner") }

  before do
    driven_by(:cuprite)

    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") do |record|
      record.name = "Manage Hotel Profile"
    end
    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    create(
      :hotel_guest_instruction,
      hotel: hotel,
      arrival_instructions: "Use the lobby entrance.",
      departure_instructions: "Leave keys at reception."
    )

    sign_in_through_ui(user)
  end

  it "keeps dirty state and Cancel behavior inside each instruction section" do
    visit hotel_guest_arrival_departure_path(hotel)

    within("#arrival-instructions") do
      expect(page).to have_button("Save", disabled: true)
      expect(page).to have_no_button("Cancel")

      fill_in "Arrival Instructions", with: "Use the side entrance."

      expect(page).to have_button("Save", disabled: false)
      expect(page).to have_button("Cancel")
    end

    within("#departure-instructions") do
      expect(page).to have_button("Save", disabled: true)
      expect(page).to have_no_button("Cancel")

      fill_in "Departure Instructions", with: "Leave keys in the box."
      click_button "Cancel"

      expect(page).to have_field("Departure Instructions", with: "Leave keys at reception.")
      expect(page).to have_button("Save", disabled: true)
      expect(page).to have_no_button("Cancel")
    end

    within("#arrival-instructions") do
      expect(page).to have_field("Arrival Instructions", with: "Use the side entrance.")
      expect(page).to have_button("Save", disabled: false)
      expect(page).to have_button("Cancel")
    end
  end
end
