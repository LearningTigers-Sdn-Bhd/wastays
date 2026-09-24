# frozen_string_literal: true

# The tablet's side of pairing: scan or type, name yourself, done.
#
# Unauthenticated by design. The pairing *is* the credential, which is why it is
# single use and measured in minutes -- see SigningDevicePairing. Nothing here
# ever puts a staff session on the tablet, which was the whole reason for
# replacing the old sign-in-then-sign-out enrolment.
class Public::SigningDevicePairingsController < ApplicationController
  # A six-character code is short enough to be worth guessing if guesses are
  # free. They are not: this is the only route that takes one, and it is capped
  # well below the rate that would make a billion-code space worth attacking.
  rate_limit to: 10, within: 1.minute, only: :lookup,
             with: -> { redirect_to pair_path, alert: "Too many attempts. Wait a minute and try again." }

  before_action :set_pairing, only: %i[show create]

  # Typing the code instead, for a tablet whose camera will not focus on a
  # monitor.
  def new
  end

  def lookup
    pairing = claimable_pairings.find_by(code: SigningDevicePairing.normalize_code(params[:code]))

    # One message for "wrong" and "expired" alike: telling a guesser which of
    # the two they hit is telling them whether the code exists.
    return redirect_to pair_path, alert: "That code is not valid. Ask the front desk for a new one." if pairing.nil?

    redirect_to pair_token_path(pairing.token)
  end

  # Confirms the property before anything is created, so a tablet that scanned
  # the wrong screen finds out here rather than after it is enrolled.
  def show
    @hotel = @pairing.hotel
    @device_label = SigningDevice::DEFAULT_LABEL
  end

  def create
    device = @pairing.claim!(label: params[:label])

    # nil means the pairing was claimed or expired between loading this page and
    # submitting it -- two tablets racing one QR, or a slow hand.
    if device.nil?
      return redirect_to pair_path,
        alert: "That pairing code has already been used. Ask the front desk for a new one."
    end

    redirect_to signing_device_path(device.public_token)
  end

  private

  # A pairing minted before the property's grant was withdrawn is no longer a
  # pairing. Scoped here so neither way in has to remember the rule.
  def claimable_pairings
    SigningDevicePairing.claimable.joins(:hotel).where(hotels: { grc_tablet_signing_enabled: true })
  end

  def set_pairing
    @pairing = claimable_pairings.find_by(token: params[:token])

    return if @pairing

    redirect_to pair_path, alert: "That pairing code has expired. Ask the front desk for a new one."
  end
end
