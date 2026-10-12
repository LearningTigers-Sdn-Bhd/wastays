# frozen_string_literal: true

require "rails_helper"

# Every way an OTA booking can name its booker and its guest, and which guest
# profile it should end up on. A wrong match shows one person's ID and stay
# history at another's check-in; a missed match is a duplicate staff can merge.
RSpec.describe "Channel guest matching" do
  let(:hotel) { create(:hotel) }

  def ingest(details = {}, booking: nil, previous_guest_name: nil, **more)
    booking ||= create(:booking, hotel:)
    ChannelManagers::InitializeBookingConnections.call!(
      booking:, guest_details: details.merge(more), previous_guest_name:
    )[:booking_guest]
  end

  def profile(name:, email: nil, phone: nil, **attrs)
    create(:guest, name:, email:, phone:, government_id: nil, **attrs)
  end

  describe "booker is the guest staying" do
    it "creates a profile with their own email and phone the first time" do
      guest = ingest(name: "Alice Tan", booker_name: "Alice Tan", email: "alice@mail.com", phone: "+60111").guest

      expect(guest).to have_attributes(name: "Alice Tan", email: "alice@mail.com", phone: "+60111")
    end

    it "finds them again on a repeat booking" do
      alice = profile(name: "Alice Tan", email: "alice@mail.com")

      expect(ingest(name: "Alice Tan", booker_name: "Alice Tan", email: "alice@mail.com").guest).to eq(alice)
    end

    it "matches through case, accents, punctuation, spacing and word order" do
      jose = profile(name: "José Tan", email: "jose@mail.com")

      expect(ingest(name: "TAN,  jose", booker_name: "TAN,  jose", email: " JOSE@MAIL.COM ").guest).to eq(jose)
    end

    it "matches non-Latin names exactly" do
      chen = profile(name: "陈小明", email: "chen@mail.com")

      expect(ingest(name: "陈小明", booker_name: "陈小明", email: "chen@mail.com").guest).to eq(chen)
    end

    it "matches on phone when there is no email" do
      alice = profile(name: "Alice Tan", phone: "+60111")

      expect(ingest(name: "Alice Tan", booker_name: "Alice Tan", phone: "+60111").guest).to eq(alice)
    end

    it "keeps a family sharing one email apart" do
      wife = profile(name: "Mei Ling Tan", email: "family@mail.com")

      husband = ingest(name: "David Tan", booker_name: "David Tan", email: "family@mail.com").guest

      expect(husband).not_to eq(wife)
      expect(husband.name).to eq("David Tan")
    end

    it "picks the profile with the right name when several share the email" do
      profile(name: "Mei Ling Tan", email: "family@mail.com")
      david = profile(name: "David Tan", email: "family@mail.com")

      expect(ingest(name: "David Tan", booker_name: "David Tan", email: "family@mail.com").guest).to eq(david)
    end

    it "does not treat a shortened name as the same person" do
      alice = profile(name: "Alice Tan", email: "alice@mail.com")

      expect(ingest(name: "Alice", booker_name: "Alice", email: "alice@mail.com").guest).not_to eq(alice)
    end

    it "ignores a profile that was deleted" do
      gone = profile(name: "Alice Tan", email: "alice@mail.com", discarded_at: Time.current)

      expect(ingest(name: "Alice Tan", booker_name: "Alice Tan", email: "alice@mail.com").guest).not_to eq(gone)
    end

    it "never matches on the 'phone not captured' placeholder" do
      placeholder = "#{Guest::PHONE_NOT_CAPTURED}-1"
      other = profile(name: "Alice Tan", phone: placeholder)

      expect(ingest(name: "Alice Tan", booker_name: "Alice Tan", phone: placeholder).guest).not_to eq(other)
    end

    it "treats a booking with no booker name on record the same way (older payloads)" do
      alice = profile(name: "Alice Tan", email: "alice@mail.com")

      expect(ingest(name: "Alice Tan", email: "alice@mail.com").guest).to eq(alice)
    end
  end

  describe "booker is someone else (agent, company, parent)" do
    it "files the guest under their own name without the booker's contact" do
      guest = ingest(name: "Alice Tan", booker_name: "Sarah Agent", email: "sarah@agency.com", phone: "+60999").guest

      expect(guest).to have_attributes(name: "Alice Tan", email: nil, phone: nil)
    end

    it "keeps the booker's contact on the booking itself" do
      booking = create(:booking, hotel:, guest_email: "sarah@agency.com", guest_phone: "+60999")

      ingest({ name: "Alice Tan", booker_name: "Sarah Agent", email: "sarah@agency.com" }, booking:)

      expect(booking.reload).to have_attributes(guest_email: "sarah@agency.com", guest_phone: "+60999")
    end

    it "gives each guest of one agent their own profile (the original bug)" do
      alice = ingest(name: "Alice Tan", booker_name: "Sarah Agent", email: "sarah@agency.com").guest
      bob = ingest(name: "Bob Lim", booker_name: "Sarah Agent", email: "sarah@agency.com").guest

      expect(bob).not_to eq(alice)
      expect(bob.name).to eq("Bob Lim")
    end

    it "never lands on the agent's own profile" do
      sarah = profile(name: "Sarah Agent", email: "sarah@agency.com")

      expect(ingest(name: "Alice Tan", booker_name: "Sarah Agent", email: "sarah@agency.com").guest).not_to eq(sarah)
    end

    it "never lands on a profile matched by the booker's contact, even with the guest's name" do
      # e.g. a profile some earlier import filed under the guest's name but the agent's email
      wrongly_filed = profile(name: "Alice Tan", email: "sarah@agency.com")

      expect(ingest(name: "Alice Tan", booker_name: "Sarah Agent", email: "sarah@agency.com").guest).not_to eq(wrongly_filed)
    end

    it "accepts a duplicate for an agent's repeat guest rather than guess" do
      first = ingest(name: "Alice Tan", booker_name: "Sarah Agent", email: "sarah@agency.com").guest
      second = ingest(name: "Alice Tan", booker_name: "Sarah Agent", email: "sarah@agency.com").guest

      expect(second).not_to eq(first)
    end
  end

  describe "a government ID on the booking" do
    it "wins over everything else, even when someone else booked" do
      alice = create(:guest, name: "Alice Tan", government_id: "a1234567", email: "alice@mail.com")

      matched = ingest(name: "Alice Tan", booker_name: "Sarah Agent", email: "sarah@agency.com", government_id: " A1234567 ").guest

      expect(matched).to eq(alice)
    end
  end

  describe "a later revision names a different guest" do
    it "renames a profile this booking alone created" do
      booking = create(:booking, hotel:)
      original = ingest({ name: "Alice Tan", booker_name: "Sarah Agent" }, booking:).guest

      ingest({ name: "Alicia Tan", booker_name: "Sarah Agent" }, booking:)

      expect(booking.booking_guests.find_by(role: "primary").guest).to eq(original)
      expect(original.reload.name).to eq("Alicia Tan")
    end

    it "moves the booking to the new guest's profile when the old one is someone's real profile" do
      booking = create(:booking, hotel:)
      alice = profile(name: "Alice Tan", email: "alice@mail.com")
      create(:booking_guest, booking:, guest: alice, is_primary: true)

      ingest({ name: "Bob Lim", booker_name: "Sarah Agent", email: "sarah@agency.com" }, booking:, previous_guest_name: "Alice Tan")

      primary = booking.booking_guests.find_by(role: "primary")
      expect(primary.guest).not_to eq(alice)
      expect(primary.guest.name).to eq("Bob Lim")
      expect(alice.reload.name).to eq("Alice Tan")
    end

    it "keeps a real profile through a respelling" do
      booking = create(:booking, hotel:)
      alice = profile(name: "Alice Tan", email: "alice@mail.com")
      create(:booking_guest, booking:, guest: alice, is_primary: true)

      ingest({ name: "Alice Tan Mei Ling", booker_name: "Alice Tan Mei Ling" }, booking:, previous_guest_name: "Alice Tan")

      expect(booking.booking_guests.find_by(role: "primary").guest).to eq(alice)
      expect(alice.reload.name).to eq("Alice Tan")
    end

    it "changes nothing once the guest has checked in" do
      booking = create(:booking, hotel:, status: "checked_in", checked_in_at: Time.current)
      alice = profile(name: "Alice Tan", email: "alice@mail.com")
      create(:booking_guest, booking:, guest: alice, is_primary: true)

      ingest({ name: "Bob Lim", booker_name: "Bob Lim" }, booking:, previous_guest_name: "Alice Tan")

      expect(booking.booking_guests.find_by(role: "primary").guest).to eq(alice)
    end

    it "changes nothing once the guest has started online pre-check-in" do
      booking = create(:booking, hotel:, pre_checkin_status: "in_progress")
      alice = profile(name: "Alice Tan", email: "alice@mail.com")
      create(:booking_guest, booking:, guest: alice, is_primary: true)

      ingest({ name: "Bob Lim", booker_name: "Bob Lim" }, booking:, previous_guest_name: "Alice Tan")

      expect(booking.booking_guests.find_by(role: "primary").guest).to eq(alice)
    end

    it "keeps a profile staff chose when the OTA sends the same guest again" do
      # The OTA only ever named the agent; staff linked the real guest by hand.
      booking = create(:booking, hotel:)
      alice = profile(name: "Alice Tan", email: "alice@mail.com")
      create(:booking_guest, booking:, guest: alice, is_primary: true)

      ingest({ name: "Sarah Agent", booker_name: "Sarah Agent" }, booking:, previous_guest_name: "Sarah Agent")

      expect(booking.booking_guests.find_by(role: "primary").guest).to eq(alice)
    end

    it "does nothing when the name is the same" do
      booking = create(:booking, hotel:)
      alice = profile(name: "Alice Tan", email: "alice@mail.com")
      create(:booking_guest, booking:, guest: alice, is_primary: true)

      expect { ingest({ name: "alice TAN", booker_name: "Alice Tan" }, booking:) }.not_to change(Guest, :count)
      expect(booking.booking_guests.find_by(role: "primary").guest).to eq(alice)
    end
  end
end
