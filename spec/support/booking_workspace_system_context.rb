# frozen_string_literal: true

# Shared setup for the booking-workspace system specs. Establishes an approved
# hotel, a front-desk user with booking permissions, and a booking with one
# room, a primary guest, and a primary folio. Signs in through the fast
# test-only route rather than the login form.
#
# Deposit, housekeeping, and complaint fixtures are intentionally NOT created
# here: only the navigation spec asserts on them, so it builds them itself.
RSpec.shared_context "booking workspace system setup" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "hotel_staff") }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }
  let(:booking) { create(:booking, hotel: hotel) }

  before do |example|
    driven_by(example.metadata[:js] ? :cuprite : :rack_test)
    %w[view_bookings manage_bookings].each do |slug|
      role.permissions << Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    end
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    create(:booking_room, booking: booking)
    guest = create(:guest, email: "hanami@mail.com", phone: "+60123451234", government_id: "P4821")
    create(:booking_guest, booking: booking, guest: guest, is_primary: true)
    create(:booking_folio, booking: booking, hotel: hotel, is_primary: true)

    sign_in_as_system(user)
  end

  after do |example|
    page.current_window.resize_to(1400, 1400) if example.metadata[:mobile] && Capybara.current_driver == :cuprite
  end
end
