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
    click_button "No additional staff for now"

    expect(page).to have_current_path(hotel_onboarding_section_path(hotel, section_key: "taxes_fees"))
    expect(page).to have_text("No additional staff will be invited for now")

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
end
