# frozen_string_literal: true

# A short-lived, single-use invitation for a tablet to become a signing device.
#
# The desk mints one and shows it; the tablet scans the QR or types the code and
# enrols itself. Nothing about that flow asks the tablet to hold staff
# credentials, which is the point -- a device left on a counter should never
# have been able to sign in to the portal in the first place.
#
# Two ways in, one pairing: `token` is the long random inside the QR, `code` is
# the short one a person can read off a screen. A tablet with a broken camera is
# not locked out, and a code short enough to type is not the only lock -- it
# expires in minutes and dies on first use.
class SigningDevicePairing < ApplicationRecord
  # Long enough that the QR's URL is not worth guessing.
  TOKEN_BYTES = 20

  # No O/0 or I/1: the code is read off one screen and typed into another, and
  # a character pair that looks alike costs more in failed attempts than the
  # entropy it adds. 32**6 is still about a billion codes.
  CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  CODE_LENGTH = 6

  # Long enough to walk a tablet over from the back office, short enough that a
  # QR left up on a screen is worthless by the time anyone else sees it.
  LIFESPAN = 10.minutes

  belongs_to :hotel
  belongs_to :created_by_user, class_name: "User", optional: true
  belongs_to :signing_device, optional: true

  validates :token, presence: true, uniqueness: true
  validates :code, presence: true, uniqueness: true
  validates :expires_at, presence: true

  before_validation :generate_secrets, on: :create
  before_validation :set_expiry, on: :create

  # The only scope anything should claim through. A pairing that is expired or
  # already used is not "a pairing with a flag set" -- it is not a pairing.
  scope :claimable, -> { where(claimed_at: nil).where(expires_at: Time.current..) }

  # Unclaimed and past its window. Swept when a new one is minted rather than on
  # a schedule: the table only grows when someone is standing at this screen.
  scope :stale, -> { where(claimed_at: nil).where(expires_at: ...Time.current) }

  # Typed by a person, so it arrives however their keyboard felt: lowercase,
  # spaced, or hyphenated the way it was displayed.
  def self.normalize_code(value)
    value.to_s.upcase.gsub(/[^A-Z0-9]/, "")
  end

  def self.claim_by_code(hotel:, code:)
    normalized = normalize_code(code)
    return nil if normalized.length != CODE_LENGTH

    hotel.signing_device_pairings.claimable.find_by(code: normalized)
  end

  def claimed? = claimed_at.present?
  def expired? = expires_at <= Time.current
  def claimable? = !claimed? && !expired?

  # Displayed split down the middle -- "K7M24Q" reads as "K7M-24Q", which is
  # markedly easier to carry across a lobby in someone's head.
  def display_code
    half = CODE_LENGTH / 2
    "#{code[0...half]}-#{code[half..]}"
  end

  def seconds_remaining = [ (expires_at - Time.current).to_i, 0 ].max

  # Turns the pairing into a device, or returns nil if it was claimed or expired
  # between the tablet loading the page and submitting it. Locked and re-checked
  # inside the transaction so two tablets racing the same QR cannot both win.
  def claim!(label:)
    device = nil

    transaction do
      lock!
      return nil unless claimable?

      device = hotel.signing_devices.create!(label: label.to_s.strip.presence || SigningDevice::DEFAULT_LABEL)
      update!(claimed_at: Time.current, signing_device: device)
    end

    device
  end

  private

  def generate_secrets
    self.token ||= SecureRandom.hex(TOKEN_BYTES)
    self.code ||= loop do
      candidate = Array.new(CODE_LENGTH) { CODE_ALPHABET.chars.sample(random: SecureRandom) }.join
      break candidate unless SigningDevicePairing.exists?(code: candidate)
    end
  end

  def set_expiry
    self.expires_at ||= LIFESPAN.from_now
  end
end
