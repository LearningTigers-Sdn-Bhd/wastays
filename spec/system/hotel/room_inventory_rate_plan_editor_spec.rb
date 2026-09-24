require "rails_helper"

RSpec.describe "Room Inventory rate plan editor", type: :system, js: true do
  let(:hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user, account: hotel.account, role: "admin") }
  let(:role) { create(:role, account: hotel.account, slug: "hotel_owner", name: "Hotel Owner") }
  let!(:villa) do
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "Villa", room_number_mode: "custom", quantity: 1, base_price: 250.0, max_adults: 2, room_numbers: %w[V1] }
    )
  end
  let!(:full_board) do
    create(:rate_plan, :custom, hotel: hotel, name: "Full Board").tap do |plan|
      create(:room_type_rate_plan, rate_plan: plan, room_type: villa, pricing_value: 400)
    end
  end

  before do
    driven_by(:cuprite)

    %w[manage_account manage_hotel_profile].each do |slug|
      permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.titleize }
      RolePermission.find_or_create_by!(role: role, permission: permission)
    end
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
  end

  def open_editor
    visit hotel_room_types_path(hotel)
    # Same request the row menu's "Edit rate" link makes into the sheet frame.
    url = edit_hotel_rate_plan_path(hotel, full_board, room_type_id: villa.id)
    page.execute_script("document.getElementById('settings_action_sheet').src = arguments[0]", url)
    expect(page).to have_button("Save rate plan", wait: 10)
  end

  it "shows a worked example for a long-stay discount as it is filled in" do
    open_editor
    click_button "Add discount"

    within("[data-role='stay-discount-row']") do
      expect(page).to have_text("Enter the nights and the discount to see an example.")

      find("input[name$='[min_nights]']").fill_in(with: "3")
      find("input[name$='[value]']").fill_in(with: "15")
      expect(page).to have_text("Example: a 3-night stay at MYR 400 a night")
      expect(page).to have_text("Nights 1–3: MYR 400 → MYR 340")
      expect(page).to have_text("Total: MYR 1,200 → MYR 1,020 (guest saves MYR 180)")

      find("select[name$='[from_night]']").select("Night 2")
      expect(page).to have_text("Night 1: MYR 400 (normal price)")
      expect(page).to have_text("Nights 2–3: MYR 400 → MYR 340")
      expect(page).to have_text("Total: MYR 1,200 → MYR 1,080 (guest saves MYR 120)")

      find("select[name$='[discount_type]']").select("Fixed amount per night")
      find("input[name$='[value]']").fill_in(with: "50")
      expect(page).to have_text("Nights 2–3: MYR 400 → MYR 350")
      expect(page).to have_css("[data-stay-discount-example-target='unit']", text: "MYR")
    end
  end
end
