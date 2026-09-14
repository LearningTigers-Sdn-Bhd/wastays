# frozen_string_literal: true

# A tablet enrolled to collect guest signatures on registration cards.
#
# The front desk pushes a stay to the device and the tablet walks that stay's
# guests, one card at a time, until none are left. The queue is not stored as a
# list: it is derived from who has yet to sign, so a card signed on some other
# surface drops out of it, and a guest who walks away mid-signature is still
# next in line when the tablet comes back.
class SigningDevice < ApplicationRecord
  # Long enough that the URL is not worth guessing, and it is the only thing
  # standing between a stranger and a stream of other people's passport numbers.
  TOKEN_BYTES = 20

  # The one region of the idle screen the desk can write to. Replacing it is
  # how a tablet is told to move: the incoming element carries the path, and
  # its Stimulus controller navigates as soon as it connects.
  COMMAND_REGION_ID = "signing_device_command"

  # How stale `last_seen_at` may get before the desk is told a tablet is not
  # listening. The idle screen beats every 20 seconds, so this is three missed
  # beats -- long enough to ride out a slow network, short enough that staff
  # are not sent to a dead tablet.
  LIVENESS_WINDOW = 60.seconds

  belongs_to :hotel
  belongs_to :current_booking, class_name: "Booking", optional: true

  validates :public_token, presence: true, uniqueness: true
  validates :label, presence: true

  before_validation :generate_public_token, on: :create

  scope :recently_seen_first, -> { order(Arel.sql("last_seen_at DESC NULLS LAST")) }

  def idle? = current_booking.blank?

  # Whether the tablet is actually listening right now, as opposed to having
  # loaded the idle screen at some point and died. Only the idle screen beats,
  # and only while its stream is connected, so this answers the question the
  # desk is really asking: will pressing send do anything?
  def live? = last_seen_at.present? && last_seen_at > LIVENESS_WINDOW.ago

  # Holding a stay that still owes signatures. Derived, like the queue itself,
  # so a tablet left on a stay whose guests all signed elsewhere frees itself
  # without anyone clearing it.
  def busy? = pending_booking_guests.any?

  # The guests of the stay in hand who still owe a signature, in the order the
  # desk would work through them: the primary guest first, then the rest as
  # they were added.
  def pending_booking_guests
    return [] if current_booking.blank?

    current_booking
      .booking_guests
      .includes(:guest, :guest_registration_card)
      .sort_by { |booking_guest| [ booking_guest.primary? ? 0 : 1, booking_guest.id ] }
      .reject { |booking_guest| booking_guest.guest_registration_card&.signed? }
  end

  def next_booking_guest = pending_booking_guests.first

  # Built rather than found when a guest has never had a card: the first push is
  # usually also the first time anyone has asked this guest to sign.
  def next_card
    booking_guest = next_booking_guest
    return nil if booking_guest.blank?

    booking_guest.guest_registration_card ||
      booking_guest.build_guest_registration_card(hotel: hotel, booking: current_booking)
  end

  def hand_stay(booking) = update!(current_booking: booking)

  def release! = update!(current_booking: nil)

  def touch_seen! = update_column(:last_seen_at, Time.current)

  private

  def generate_public_token
    self.public_token ||= SecureRandom.hex(TOKEN_BYTES)
  end
end
