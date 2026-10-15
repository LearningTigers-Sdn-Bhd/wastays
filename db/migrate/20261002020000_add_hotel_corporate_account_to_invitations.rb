# frozen_string_literal: true

# A corporate invitation can claim an account that already exists, instead of
# creating a new one on acceptance. The reservation importer creates a corporate
# account for every travel agent it finds, with bookings already on it and nobody
# able to sign in; inviting a contact to *that* account is how an agent gets in
# without ending up with a second, empty account of their own.
class AddHotelCorporateAccountToInvitations < ActiveRecord::Migration[8.1]
  def change
    add_reference :invitations, :hotel_corporate_account, null: true, foreign_key: true, index: true
  end
end
