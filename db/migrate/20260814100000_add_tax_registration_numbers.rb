# frozen_string_literal: true

# Gives a hotel somewhere to record the numbers that prove it may charge what it
# charges.
#
# Malaysian hotels must quote a company TIN and SSM number on their documents, plus
# a registration number for each tax they collect: an SST number, a Tourism Tax
# number, and whatever licence number the local council issues (DBKK in Sabah, and
# a growing list of state levies elsewhere). The app stored what a hotel charges
# but never these, so none of them could reach an invoice.
#
# They land in two places because they are two different kinds of fact. TIN and SSM
# identify the business itself and belong to the property. A registration number
# belongs to one specific tax — hence the column on hotel_taxes, which gives every
# future state levy a home for its number without another migration. SST and
# Tourism Tax are carried as columns on hotels rather than as hotel_taxes rows, so
# their two numbers sit alongside the existing sst_enabled / tourism_tax_enabled
# pair.
#
# All nullable and unindexed: these are reference values printed on documents, not
# lookup keys, and a hotel is perfectly usable before it has them.
class AddTaxRegistrationNumbers < ActiveRecord::Migration[8.1]
  def change
    add_column :hotels, :tin, :string
    add_column :hotels, :ssm_number, :string
    add_column :hotels, :sst_registration_number, :string
    add_column :hotels, :tourism_tax_registration_number, :string

    add_column :hotel_taxes, :registration_number, :string
  end
end
