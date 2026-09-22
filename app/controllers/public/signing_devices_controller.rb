# frozen_string_literal: true

# The tablet's own two pages: the idle screen it waits on, and the hop that
# hands it the next card.
#
# `next` is a redirect rather than a page so the tablet always lands on the
# card page the guest would have opened themselves — one signing surface, not
# two. It also decides when the stay is finished, which is why the tablet is
# sent back through here after every signature rather than being told up front
# how many guests to expect.
class Public::SigningDevicesController < ApplicationController
  before_action :set_device
  before_action :remember_device

  def show
    @device.touch_seen!

    # A tablet that was asleep or backgrounded when the desk pressed send missed
    # the broadcast entirely -- the socket it would have arrived on did not
    # exist. But the stay was still handed over, so the work is sitting here
    # waiting. Picking it up on load is what lets a property leave the screen
    # off between guests: wake the tablet and it opens on the card, instead of
    # showing "Ready to sign" while holding a stay it never mentions.
    return redirect_to next_signing_device_path(@device.public_token) if @device.busy?

    @hotel = @device.hotel
  end

  # Proof of life from the idle screen, sent only while its stream is actually
  # connected. `show` alone cannot carry this: a tablet that loaded the page
  # and then slept looks, to the desk, exactly like one that is waiting.
  def heartbeat
    @device.touch_seen!
    head :no_content
  end

  def next
    card = @device.next_card

    if card.nil?
      # Nothing left to sign. Drop the stay before going idle so the screen
      # cannot be nudged back into someone's registration card afterwards.
      @device.release!
      return redirect_to signing_device_path(@device.public_token),
        notice: "All guests have signed. Thank you."
    end

    card.save! if card.new_record?
    redirect_to guest_registration_card_path(card.public_token)
  end

  private

  # Scoped to properties that still have the feature, rather than found and then
  # checked: a withdrawn grant should stop a tablet the same way an unknown
  # token does, and there is then no second check to forget.
  def set_device
    @device = SigningDevice.joins(:hotel)
      .where(hotels: { grc_tablet_signing_enabled: true })
      .find_by!(public_token: params[:token])
  end

  # The card pages are reached by the guest's own token and know nothing about
  # tablets, so the device rides along in the session instead. That keeps the
  # device token out of the URL the guest is looking at, and out of anything
  # that URL might be pasted into.
  def remember_device
    session[:signing_device_token] = @device.public_token
  end
end
