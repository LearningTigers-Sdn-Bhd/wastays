# frozen_string_literal: true

# A consolidated e-invoice is ONE document at LHDN covering many bookings, so
# every submission row in that batch carries the same UUID. The original unique
# index did not allow for that, which meant consolidation failed with a unique
# violation as soon as a hotel had more than one qualifying booking in a month
# - i.e. in every realistic month.
#
# Uniqueness still matters for individually-filed documents, so it is kept for
# those and relaxed only for consolidated rows.
class AllowSharedUuidForConsolidatedSubmissions < ActiveRecord::Migration[8.1]
  def up
    remove_index :e_invoice_submissions, :uuid
    add_index :e_invoice_submissions, :uuid,
              unique: true,
              where: "uuid IS NOT NULL AND consolidated = false",
              name: "index_e_invoice_submissions_on_individual_uuid"
    add_index :e_invoice_submissions, :uuid,
              where: "uuid IS NOT NULL",
              name: "index_e_invoice_submissions_on_uuid"
  end

  def down
    remove_index :e_invoice_submissions, name: "index_e_invoice_submissions_on_individual_uuid"
    remove_index :e_invoice_submissions, name: "index_e_invoice_submissions_on_uuid"
    add_index :e_invoice_submissions, :uuid, unique: true, where: "uuid IS NOT NULL"
  end
end
