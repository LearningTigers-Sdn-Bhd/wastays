# frozen_string_literal: true

# Lets a prospect exist without a phone number.
#
# Every prospect so far arrived from the external bot, which always knows the
# sender's number. A visitor typing into the chat on the public concierge page
# does not have one, and demanding a phone before the first question is the
# fastest way to lose the enquiry. `public_id` is already the durable handle
# for that visitor, so nothing else needs to change.
#
# The unique index on (hotel_id, phone_number) survives untouched: Postgres
# treats NULLs as distinct, so any number of anonymous prospects coexist while
# a real number still cannot be claimed twice in one hotel.
class AllowAnonymousProspects < ActiveRecord::Migration[8.1]
  def change
    change_column_null :prospects, :phone_number, true
  end
end
