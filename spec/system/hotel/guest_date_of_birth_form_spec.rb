require "rails_helper"

RSpec.describe "Hotel guest DOB form behavior", type: :system, js: true do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account: account, plan: plan, status: "approved") }
  let(:user) { create(:user, account: account) }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let!(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe") }
  let!(:guest) do
    create(
      :guest,
      name: "Kenji Sato",
      email: "kenji@example.com",
      phone: "+60129990000",
      country: "Japan",
      gender: "male",
      document_type: "passport",
      government_id: "P1234567",
      date_of_birth: Date.new(1992, 4, 5),
      created_by_hotel: hotel
    )
  end

  before do
    driven_by(:cuprite)

    permission = Permission.find_by(slug: "manage_bookings") || create(:permission, slug: "manage_bookings", name: "Manage Bookings")
    create(:role_permission, role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "unified_guest_profile"), enabled: true)

    sign_in_through_ui(user)
  end

  it "populates DOB from autocomplete and only autofills from Malaysian IC when DOB is blank" do
    pending("The new-booking form (_form.html.erb) no longer renders " \
      "_guest_information.html.erb (guest-autocomplete/guest-dob controllers) at " \
      "all — it has its own inline 'Guest name' field with no autocomplete or DOB " \
      "autofill. Those controllers are still used elsewhere (e.g. guest_details " \
      "editing in the Booking Control Panel), so this spec needs to target wherever " \
      "the feature actually lives now, not new-booking creation.")
    visit hotel_booking_transaction_new_booking_path(hotel)

    full_name = find_field("Full Name")
    full_name.click
    full_name.native.send_keys("Kenji")
    expect(page).to have_css('[role="option"]', text: "Kenji Sato")
    find('[role="option"]', text: "Kenji Sato").click

    expect(page).to have_field("Date of Birth", with: "1992-04-05")

    page.execute_script(<<~JS)
      const country = document.getElementById("booking_guest_country")
      country.value = "Malaysia"
      country.dispatchEvent(new Event("input", { bubbles: true }))

      const documentType = document.getElementById("booking_guest_document_type")
      documentType.value = "ic"
      documentType.dispatchEvent(new Event("change", { bubbles: true }))

      const dateOfBirth = document.getElementById("booking_guest_date_of_birth")
      dateOfBirth.value = ""

      const governmentId = document.getElementById("booking_guest_government_id")
      governmentId.value = "900101011234"
      governmentId.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    expect(page).to have_field("Date of Birth", with: "1990-01-01")

    page.execute_script(<<~JS)
      const dateOfBirth = document.getElementById("booking_guest_date_of_birth")
      dateOfBirth.value = "1991-02-03"

      const governmentId = document.getElementById("booking_guest_government_id")
      governmentId.value = "880202011234"
      governmentId.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    expect(page).to have_field("Date of Birth", with: "1991-02-03")

    page.execute_script(<<~JS)
      const country = document.getElementById("booking_guest_country")
      country.value = "Japan"
      country.dispatchEvent(new Event("input", { bubbles: true }))

      const documentType = document.getElementById("booking_guest_document_type")
      documentType.value = "ic"
      documentType.dispatchEvent(new Event("change", { bubbles: true }))

      const dateOfBirth = document.getElementById("booking_guest_date_of_birth")
      dateOfBirth.value = ""

      const governmentId = document.getElementById("booking_guest_government_id")
      governmentId.value = "900101011234"
      governmentId.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    expect(page).to have_field("Date of Birth", with: "")

    page.execute_script(<<~JS)
      const country = document.getElementById("booking_guest_country")
      country.value = "Malaysia"
      country.dispatchEvent(new Event("input", { bubbles: true }))

      const documentType = document.getElementById("booking_guest_document_type")
      documentType.value = "passport"
      documentType.dispatchEvent(new Event("change", { bubbles: true }))

      const dateOfBirth = document.getElementById("booking_guest_date_of_birth")
      dateOfBirth.value = ""

      const governmentId = document.getElementById("booking_guest_government_id")
      governmentId.value = "900101011234"
      governmentId.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    expect(page).to have_field("Date of Birth", with: "")
  end
end
