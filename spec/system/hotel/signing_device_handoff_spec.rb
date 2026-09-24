# frozen_string_literal: true

require "rails_helper"

# The tablet's half of the loop: once told to move, it should walk every guest
# who still owes a signature and then show nobody's details at all.
#
# The push itself is not driven here. The test cable adapter records broadcasts
# rather than delivering them, and several specs depend on that, so a browser in
# this suite never receives one. `next` is therefore visited directly, which is
# exactly what the broadcast asks the tablet to do -- the wire between the two
# is covered in spec/requests/hotel_portal/signing_handoffs_spec.rb.
RSpec.describe "Signing device queue", frozen_time: :business_day, type: :system do
  include_context "booking workspace system setup"

  SIGNATURE_PAD = '[data-signature-target="canvas"]'

  let!(:device) { hotel.signing_devices.create!(label: "Front desk tablet") }
  let!(:second_booking_guest) do
    create(:booking_guest, booking: booking, guest: create(:guest, name: "Second Guest"), is_primary: false)
  end

  before do
    hotel.update!(guest_registration_card_terms: "House rules apply.",
                  grc_tablet_signing_enabled: true)
  end

  it "walks every unsigned guest, then returns to an idle screen", js: true do
    visit signing_device_path(device.public_token)
    expect(page).to have_content("Ready to sign")
    expect(page).to have_content("Front desk tablet")

    device.hand_stay(booking)

    # First guest. Headings on this page are uppercased in CSS, so the assertions
    # go through the signature pad and the field ids, which styling cannot move.
    visit next_signing_device_path(device.public_token)
    expect(page).to have_css(SIGNATURE_PAD)
    first_card_path = current_path
    first_signer = find_by_id("guest_registration_card_signer_name").value
    sign_here

    # Straight on to the guest who has not signed, with no trip back to the desk.
    #
    # Waiting on the path rather than the pad: both cards carry a pad, so
    # `have_css` matches the page being navigated away from and the name below
    # is then read off the old form. The path is the only thing that differs
    # while the swap is in flight.
    expect(page).to have_no_current_path(first_card_path, ignore_query: true)
    expect(page).to have_css(SIGNATURE_PAD)
    expect(find_by_id("guest_registration_card_signer_name").value).not_to eq(first_signer)
    sign_here

    # Nothing left: the stay is let go and the screen holds no guest's details.
    expect(page).to have_content("Ready to sign")
    expect(page).to have_no_css(SIGNATURE_PAD)
    expect(page).to have_no_content(second_booking_guest.guest.name)
    expect(device.reload.current_booking).to be_nil

    signed = booking.booking_guests.map { |booking_guest| booking_guest.reload.guest_registration_card&.signed? }
    expect(signed).to all(be(true))
  end

  it "sends a tablet with nothing to do back to idle rather than to a card", js: true do
    device.hand_stay(booking)
    booking.booking_guests.each do |booking_guest|
      create(:guest_registration_card, :signed, hotel: hotel, booking: booking, booking_guest: booking_guest)
    end

    visit next_signing_device_path(device.public_token)

    expect(page).to have_content("Ready to sign")
    expect(device.reload.current_booking).to be_nil
  end

  # Fills in what a finished signature leaves behind rather than drawing one.
  # The pad is signature_pad's, and it publishes a stroke only through its own
  # `endStroke`, which synthesised pointer events do not reliably raise. What is
  # under test here is the walk from one guest to the next, not the pad.
  def sign_here
    execute_script(<<~JS)
      const input = document.querySelector('[data-signature-target="input"]')
      input.value = "data:image/png;base64,iVBORw0KGgo="
      input.setCustomValidity("")
    JS
    click_button "Sign registration card"
  end
end
