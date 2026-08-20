# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::GuestRegistrationCardEmails", type: :request do
  let(:hotel) { create(:hotel, guest_registration_card_terms: "Valid photo ID is required at check-in.") }
  let(:booking) { create(:booking, hotel: hotel, guest_email: "guest@example.com") }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }

  def grant_permission(role, slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  before do
    grant_permission(role, "manage_bookings")
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
    booking.create_guest_registration_card!(hotel: hotel)
  end

  it "queues the card to the guest and records the delivery" do
    expect {
      post hotel_booking_guest_registration_card_email_path(hotel, booking)
    }.to change(NotificationDelivery, :count).by(1)

    delivery = NotificationDelivery.last
    expect(delivery.notification_type).to eq("guest_registration_card")
    expect(delivery.channel).to eq("email")
    expect(delivery.trigger_event).to eq("manual")
    expect(delivery.payload["recipient_email"]).to eq("guest@example.com")
    expect(flash[:notice]).to include("guest@example.com")
  end

  it "lets staff send the card more than once" do
    expect {
      2.times { post hotel_booking_guest_registration_card_email_path(hotel, booking) }
    }.to change(NotificationDelivery, :count).by(2)
  end

  it "refuses to send when the booking has no email address" do
    booking.update_columns(guest_email: nil)

    expect {
      post hotel_booking_guest_registration_card_email_path(hotel, booking)
    }.not_to change(NotificationDelivery, :count)

    expect(flash[:alert]).to eq("This booking has no guest email address to send to.")
  end

  it "refuses to send when the hotel has not set its Terms & Conditions" do
    hotel.update!(guest_registration_card_terms: nil)

    expect {
      post hotel_booking_guest_registration_card_email_path(hotel, booking)
    }.not_to change(NotificationDelivery, :count)

    expect(flash[:alert]).to eq("Set a Terms & Conditions policy in Settings before sending this card.")
  end

  it "links to the guest's own public copy of the card instead of attaching a PDF" do
    post hotel_booking_guest_registration_card_email_path(hotel, booking)

    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    card = booking.reload.guest_registration_card

    expect(mail.to).to eq([ "guest@example.com" ])
    expect(mail.subject).to include(booking.confirmation_token)
    expect(mail.attachments.map(&:mime_type)).not_to include("application/pdf")
    expect(mail.html_part.body.decoded).to include("/guest-registration-card/#{card.public_token}")
    expect(NotificationDelivery.last.reload.status).to eq("sent")
  end

  it "sends the specific guest's registration card token when another guest on the same booking has already signed" do
    primary_guest = create(:booking_guest, booking: booking, is_primary: true, name_snapshot: "Lee Ji-eun", email_snapshot: "lee@example.com")
    additional_guest = create(:booking_guest, booking: booking, is_primary: false, name_snapshot: "Jong Suk", email_snapshot: "jongsuk@example.com")

    primary_card = create(:guest_registration_card, hotel: hotel, booking: booking, booking_guest: primary_guest, status: "draft")
    _signed_card = create(:guest_registration_card, :signed, hotel: hotel, booking: booking, booking_guest: additional_guest, signer_name: "Jong Suk")

    post hotel_booking_guest_registration_card_email_path(hotel, booking, booking_guest_id: primary_guest.id)

    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last

    expect(mail.to).to eq([ "lee@example.com" ])
    expect(mail.html_part.body.decoded).to include("/guest-registration-card/#{primary_card.public_token}")
    expect(mail.html_part.body.decoded).not_to include("This card was signed by Jong Suk")
  end
end
