# frozen_string_literal: true

class BackfillGuestRegistrationCardPublicTokens < ActiveRecord::Migration[8.1]
  # The generate-on-create callback only ever ran for cards made after the
  # column existed. Every card from before that stayed NULL, which is what let
  # the emailed guest link crash with a nil token instead of failing loudly at
  # the source.
  class GuestRegistrationCard < ActiveRecord::Base
  end

  def up
    GuestRegistrationCard.where(public_token: nil).find_each do |card|
      card.update_column(:public_token, SecureRandom.hex(20))
    end
  end

  def down
    # Irreversible by design: clearing tokens would break any link already
    # sent to a guest.
  end
end
