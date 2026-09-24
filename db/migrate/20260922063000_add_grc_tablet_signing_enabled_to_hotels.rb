# frozen_string_literal: true

# Whether a property may collect registration card signatures on a front-desk
# tablet.
#
# Off by default and only a superadmin can turn it on. The feature puts a device
# holding guest identity data on a public counter, so it is switched on per
# property after that has been thought about -- not handed to every hotel that
# registers.
class AddGrcTabletSigningEnabledToHotels < ActiveRecord::Migration[8.1]
  def change
    add_column :hotels, :grc_tablet_signing_enabled, :boolean, default: false, null: false
  end
end
