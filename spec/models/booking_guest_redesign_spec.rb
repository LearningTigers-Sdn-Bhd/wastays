# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingGuest, type: :model do
  it "captures stay-time guest details and synchronizes the primary role" do
    guest = create(:guest, name: "Original Name", email: "guest@example.test", date_of_birth: Date.new(1990, 1, 2))
    booking_guest = create(:booking_guest, guest: guest, is_primary: true)

    expect(booking_guest).to have_attributes(
      role: "primary",
      name_snapshot: "Original Name",
      email_snapshot: "guest@example.test",
      date_of_birth_snapshot: Date.new(1990, 1, 2)
    )
    expect { guest.update!(name: "Later Name") }
      .not_to change { booking_guest.reload.name_snapshot }
  end

  it "encrypts sensitive stay-time snapshots" do
    booking_guest = create(:booking_guest, email_snapshot: "private@example.test", phone_snapshot: "+60123456789", government_id_snapshot: "A1234567")
    raw = ActiveRecord::Base.connection.select_one("SELECT email_snapshot, phone_snapshot, government_id_snapshot FROM booking_guests WHERE id = #{booking_guest.id}")

    expect(raw["email_snapshot"]).not_to include("private@example.test")
    expect(raw["phone_snapshot"]).not_to include("+60123456789")
    expect(raw["government_id_snapshot"]).not_to include("A1234567")
    expect(booking_guest.reload.email_snapshot).to eq("private@example.test")
  end

  it "keeps malformed encrypted snapshots out of the guest form" do
    guest = create(:guest, email: "profile@example.test")
    booking_guest = create(:booking_guest, guest: guest, email_snapshot: "safe@example.test")
    ActiveRecord::Base.connection.execute("UPDATE booking_guests SET email_snapshot = '{\"p\":malformed}' WHERE id = #{booking_guest.id}")

    presenter = HotelPortal::Bookings::WorkspacePresenter.new(booking_guest.reload.booking, params: { tab: "guest_details", booking_guest_id: booking_guest.id })

    # Falls through to the reusable profile rather than raising or presenting a
    # blank field that would overwrite the good value on save.
    expect(presenter.guest_details_snapshots[:email]).to eq("profile@example.test")
  end

  it "leaves the guest form field empty when both encrypted sources are unreadable" do
    guest = create(:guest, email: "profile@example.test")
    booking_guest = create(:booking_guest, guest: guest, email_snapshot: "safe@example.test")
    ActiveRecord::Base.connection.execute("UPDATE booking_guests SET email_snapshot = '{\"p\":malformed}' WHERE id = #{booking_guest.id}")
    ActiveRecord::Base.connection.execute("UPDATE guests SET email = '{\"p\":malformed}' WHERE id = #{guest.id}")

    presenter = HotelPortal::Bookings::WorkspacePresenter.new(booking_guest.reload.booking, params: { tab: "guest_details", booking_guest_id: booking_guest.id })

    expect { presenter.guest_details_snapshots }.not_to raise_error
    expect(presenter.guest_details_snapshots[:email]).to be_nil
  end

  it "allows only one primary guest per booking" do
    booking = create(:booking)
    create(:booking_guest, booking: booking, is_primary: true)

    duplicate = build(:booking_guest, booking: booking, is_primary: true)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:role]).to be_present
  end

  it "does not link the same guest to one booking twice" do
    booking_guest = create(:booking_guest)
    duplicate = build(:booking_guest, booking: booking_guest.booking, guest: booking_guest.guest)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:guest_id]).to be_present
  end
end
